#include "expp.hpp"
#include "jxl/decode.h"
#include "jxl/decode_cxx.h"
#include "stl.hpp"
#include "yielding.hpp"
#include <bit>
#include <erl_nif.h>
#include <iostream>
#include <jpeglib.h>
#include <jxl/encode.h>
#include <jxl/encode_cxx.h>
#include <jxl/resizable_parallel_runner.h>
#include <jxl/resizable_parallel_runner_cxx.h>
#include <jxl/thread_parallel_runner.h>
#include <jxl/thread_parallel_runner_cxx.h>
#include <memory>
#include <png.h>
#include <poppler/cpp/poppler-document.h>
#include <poppler/cpp/poppler-page-renderer.h>
#include <poppler/cpp/poppler-page.h>
#include <poppler/cpp/poppler-version.h>
#include <sstream>
#include <stdio.h>
#include <tiffio.h>
#include <tiffio.hxx>
#include <tuple>
#include <vector>

using namespace std;

// pixels, width, height, channels, bit_depth
typedef tuple<binary, uint32_t, uint32_t, uint32_t, uint32_t> decompress_result_t;


void jpeg_error_exit(j_common_ptr cinfo)
{
    char error_message[JMSG_LENGTH_MAX];
    (*(cinfo->err->format_message))(cinfo, error_message);
    throw erl_error<string>(error_message);
}


yielding<erl_result<decompress_result_t, string>> jpeg_decompress(std::vector<uint8_t> jpeg_bytes) noexcept
{
    struct jpeg_error_mgr err;
    struct jpeg_decompress_struct cinfo;
    yielding_timer timer;

    try
    {
        // create decompressor
        cinfo.err = jpeg_std_error(&err);
        jpeg_create_decompress(&cinfo);
        cinfo.do_fancy_upsampling = FALSE;
        err.error_exit = jpeg_error_exit;

        // set source buffer
        jpeg_mem_src(&cinfo, jpeg_bytes.data(), jpeg_bytes.size());

        // read jpeg header
        jpeg_read_header(&cinfo, TRUE);

        // decompress
        jpeg_start_decompress(&cinfo);
        unsigned output_bytes = cinfo.output_width * cinfo.output_height * cinfo.num_components;
        binary output(output_bytes);

        // read scanlines
        const auto row_stride = cinfo.output_width * cinfo.num_components;
        while (cinfo.output_scanline < cinfo.output_height)
        {
            auto row_ptr = output.data + cinfo.output_scanline * row_stride;
            jpeg_read_scanlines(&cinfo, &row_ptr, 1);

            if (timer.times_up())
            {
                co_yield nullopt;
                timer.reset();
            }
        }

        // clean up
        jpeg_finish_decompress(&cinfo);
        jpeg_destroy_decompress(&cinfo);
        co_yield Ok(make_tuple(
            move(output), cinfo.output_width, cinfo.output_height, static_cast<uint32_t>(cinfo.num_components), 8u));
    }
    catch (erl_error<string>& e)
    {
        jpeg_destroy_decompress(&cinfo);
        throw e;
    }
}


yielding<erl_result<binary, string>>
jpeg_compress(vector<uint8_t> pixels, uint32_t width, uint32_t height, uint32_t channels, int quality) noexcept
{
    struct jpeg_error_mgr err;
    struct jpeg_compress_struct cinfo;
    yielding_timer timer;

    try
    {
        // create the compressor
        cinfo.err = jpeg_std_error(&err);
        jpeg_create_compress(&cinfo);
        err.error_exit = jpeg_error_exit;

        uint8_t* buf = nullptr;
        unsigned long outsize = 0;
        jpeg_mem_dest(&cinfo, &buf, &outsize);

        cinfo.image_width = width;
        cinfo.image_height = height;
        cinfo.input_components = channels;
        cinfo.in_color_space = JCS_RGB;

        jpeg_set_defaults(&cinfo);
        jpeg_set_quality(&cinfo, quality, TRUE);

        // do the actual compression
        jpeg_start_compress(&cinfo, TRUE);
        while (cinfo.next_scanline < cinfo.image_height)
        {
            auto row = pixels.data() + cinfo.next_scanline * channels * width;
            jpeg_write_scanlines(&cinfo, &row, 1);

            if (timer.times_up())
            {
                co_yield nullopt;
                timer.reset();
            }
        }
        jpeg_finish_compress(&cinfo);

        jpeg_destroy_compress(&cinfo);

        // copy the buf to a binary objet
        binary out { size_t(outsize) };
        std::copy_n(buf, outsize, out.data);

        free(buf);  // free the buf created by jpeg_mem_dest

        co_yield Ok(std::move(out));
    }
    catch (erl_error<string>& e)
    {
        jpeg_destroy_compress(&cinfo);
        throw e;
    }
}


struct png_read_binary
{
    const vector<uint8_t>& data;
    size_t offset = 8;

    png_read_binary(const vector<uint8_t>& data)
        : data(data)
    { }

    void read(png_bytep dest, png_size_t size_to_read)
    {
        std::copy_n(this->data.data() + offset, size_to_read, dest);
        this->offset += size_to_read;
    }
};


void png_error_exit(png_structp png_ptr, const char* error_message)
{
    throw erl_error<string>(error_message);
}


yielding<erl_result<decompress_result_t, string>> png_decompress(vector<uint8_t> png_bytes)
{
    yielding_timer timer;

    // check png signature
    if (png_sig_cmp(png_bytes.data(), 0, 8))
    {
        co_yield Error("invalid png header"s);
        co_return;
    }

    png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, nullptr, png_error_exit, nullptr);
    if (!png_ptr)
    {
        co_yield Error("couldn't initialize png read struct"s);
        co_return;
    }

    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr)
    {
        co_yield Error("couldn't initialize png info struct"s);
        co_return;
    }

    try
    {
        // read metadata
        png_read_binary data_wrapper(png_bytes);
        png_set_read_fn(
            png_ptr,
            reinterpret_cast<png_voidp>(&data_wrapper),
            [](png_structp png_ptr, png_bytep dest, png_size_t size_to_read) {
                auto data_wrapper = reinterpret_cast<png_read_binary*>(png_get_io_ptr(png_ptr));
                data_wrapper->read(dest, size_to_read);
            });
        png_set_sig_bytes(png_ptr, 8);
        png_read_info(png_ptr, info_ptr);

        const png_uint_32 width = png_get_image_width(png_ptr, info_ptr);
        const png_uint_32 height = png_get_image_height(png_ptr, info_ptr);
        png_uint_32 bit_depth = png_get_bit_depth(png_ptr, info_ptr);
        png_uint_32 channels = png_get_channels(png_ptr, info_ptr);
        const png_uint_32 color_type = png_get_color_type(png_ptr, info_ptr);
        const auto interlace_type = png_get_interlace_type(png_ptr, info_ptr);

        switch (color_type)
        {
        case PNG_COLOR_TYPE_PALETTE:  // convert palette to RGB
            png_set_palette_to_rgb(png_ptr);
            channels = 3;
            break;
        case PNG_COLOR_TYPE_GRAY:  // expand 1, 2, or 4 bit grayscale to 8 bit grayscale
            if (bit_depth < 8)
                png_set_expand_gray_1_2_4_to_8(png_ptr);
            bit_depth = 8;
            break;
        }

        const unsigned int stride = width * bit_depth * channels / 8;
        binary output(height * stride);

        // Depending on whether the image is interlaced, we need to decode multiple passes
        // See https://github.com/glennrp/libpng/blob/libpng16/libpng-manual.txt and
        // libpng png_read_image's implementation
        int num_passes = 1;

        // if interlaced, we need to get the number of passes
        if (interlace_type == PNG_INTERLACE_ADAM7)
        {
            num_passes = png_set_interlace_handling(png_ptr);
            png_start_read_image(png_ptr);
        }

        for (int pass = 0; pass < num_passes; pass++)
        {
            for (size_t i = 0; i < height; i++)
            {
                png_read_row(png_ptr, reinterpret_cast<png_bytep>(output.data) + i * stride, nullptr);

                if (timer.times_up())
                {
                    co_yield nullopt;
                    timer.reset();
                }
            }
        }

        // for 16-bit data, convert from big-endian to little-endian, if necessary, b/c png stores data as big-endian
        if constexpr (std::endian::native == std::endian::little)
        {
            if (bit_depth == 16)
            {
                uint16_t* pixels_ptr = reinterpret_cast<uint16_t*>(output.data);
                auto n_elements = height * width * channels;
                for (size_t i = 0; i < n_elements; i++)
                    pixels_ptr[i] = __builtin_bswap16(pixels_ptr[i]);
            }
        }

        png_destroy_read_struct(&png_ptr, &info_ptr, nullptr);
        png_ptr = nullptr;

        co_yield Ok(make_tuple(std::move(output), width, height, channels, bit_depth));
    }
    catch (erl_error<string>& e)
    {
        if (png_ptr)
            png_destroy_read_struct(&png_ptr, &info_ptr, nullptr);
        throw e;
    }
}


yielding<erl_result<vector<png_byte>, string>>
png_compress(vector<uint8_t> pixels, uint32_t width, uint32_t height, uint32_t channels)
{
    yielding_timer timer;

    png_structp png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, nullptr, png_error_exit, nullptr);
    if (!png_ptr)
    {
        co_yield Error("couldn't initialize png write struct"s);
        co_return;
    }

    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr)
    {
        co_yield Error("[write_png_file] png_create_info_struct failed"s);
        co_return;
    }

    try
    {
        // set up the output data, as well as the callback to write into that data
        vector<png_byte> out_data;
        auto png_chunk_producer = [](png_structp png_ptr, png_bytep data, png_size_t length) {
            auto out_data_p = reinterpret_cast<vector<png_byte>*>(png_get_io_ptr(png_ptr));
            std::copy_n(data, length, std::back_inserter(*out_data_p));
        };
        png_set_write_fn(png_ptr, &out_data, png_chunk_producer, nullptr);

        // write header
        png_set_IHDR(
            png_ptr,
            info_ptr,
            width,
            height,
            8,
            PNG_COLOR_TYPE_RGB,
            PNG_INTERLACE_NONE,
            PNG_COMPRESSION_TYPE_BASE,
            PNG_FILTER_TYPE_BASE);
        png_write_info(png_ptr, info_ptr);

        // write the pixels
        const unsigned int stride = width * channels;
        for (size_t i = 0; i < height; i++)
        {
            png_write_row(png_ptr, pixels.data() + i * stride);

            if (timer.times_up())
            {
                co_yield nullopt;
                timer.reset();
            }
        }

        // cleanup
        png_write_end(png_ptr, nullptr);
        png_destroy_write_struct(&png_ptr, &info_ptr);
        png_ptr = nullptr;

        co_yield Ok(move(out_data));
    }
    catch (erl_error<string>& e)
    {
        if (png_ptr)
            png_destroy_write_struct(&png_ptr, &info_ptr);
        throw e;
    }
}


static_assert(JXL_ENC_SUCCESS == 0 && JXL_DEC_SUCCESS == 0);

#define JXL_ENSURE_SUCCESS(func, ...)                                                                                  \
    if (func(__VA_ARGS__) != 0)                                                                                        \
    {                                                                                                                  \
        return Error(#func " failed"_binary);                                                                          \
    }


JxlBasicInfo jxl_basic_info_from_pixel_format(const JxlPixelFormat& pixel_format)
{
    JxlBasicInfo basic_info;
    JxlEncoderInitBasicInfo(&basic_info);

    switch (pixel_format.data_type)
    {
    case JXL_TYPE_FLOAT:
        basic_info.bits_per_sample = 32;
        basic_info.exponent_bits_per_sample = 8;
        break;
    case JXL_TYPE_FLOAT16:
        basic_info.bits_per_sample = 16;
        basic_info.exponent_bits_per_sample = 5;
        break;
    case JXL_TYPE_UINT8:
        basic_info.bits_per_sample = 8;
        basic_info.exponent_bits_per_sample = 0;
        break;
    case JXL_TYPE_UINT16:
        basic_info.bits_per_sample = 16;
        basic_info.exponent_bits_per_sample = 0;
        break;
    }

    if (pixel_format.num_channels == 2 || pixel_format.num_channels == 4)
    {
        basic_info.alpha_exponent_bits = 0;
        if (basic_info.bits_per_sample == 32)
            basic_info.alpha_bits = 16;
        else
            basic_info.alpha_bits = basic_info.bits_per_sample;
    }
    else
    {
        basic_info.alpha_exponent_bits = 0;
        basic_info.alpha_bits = 0;
    }

    return basic_info;
}


erl_result<decompress_result_t, binary> jxl_decompress(const binary& jxl_bytes)
{
    // Multi-threaded parallel runner.
    static auto runner = JxlResizableParallelRunnerMake(nullptr);

    auto dec = JxlDecoderMake(nullptr);
    JXL_ENSURE_SUCCESS(
        JxlDecoderSubscribeEvents, dec.get(), JXL_DEC_BASIC_INFO | JXL_DEC_COLOR_ENCODING | JXL_DEC_FULL_IMAGE);
    JXL_ENSURE_SUCCESS(JxlDecoderSetParallelRunner, dec.get(), JxlResizableParallelRunner, runner.get());

    JxlDecoderSetInput(dec.get(), jxl_bytes.data, jxl_bytes.size);

    binary pixels;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t channels = 0;
    uint32_t bit_depth = 0;

    for (;;)
    {
        JxlDecoderStatus status = JxlDecoderProcessInput(dec.get());

        if (status == JXL_DEC_ERROR)
        {
            return Error("Decoder error"_binary);
        }
        else if (status == JXL_DEC_NEED_MORE_INPUT)
        {
            return Error("Error, already provided all input"_binary);
        }
        else if (status == JXL_DEC_BASIC_INFO)
        {
            JxlBasicInfo info;
            JXL_ENSURE_SUCCESS(JxlDecoderGetBasicInfo, dec.get(), &info);

            if (info.exponent_bits_per_sample != 0)
                return Error("FLOAT32 images are currently not yet supported"_binary);

            width = info.xsize;
            height = info.ysize;
            channels = info.num_color_channels + info.num_extra_channels;
            bit_depth = info.bits_per_sample;
        }
        else if (status == JXL_DEC_COLOR_ENCODING)
        {
            // Get the ICC color profile of the pixel data
            // size_t icc_size;
            // JXL_ENSURE_SUCCESS(
            //     JxlDecoderGetICCProfileSize, dec.get(), &format, JXL_COLOR_PROFILE_TARGET_DATA, &icc_size);
            // icc_profile->resize(icc_size);
            // if (JxlDecoderGetColorAsICCProfile(
            //         dec.get(), &format, JXL_COLOR_PROFILE_TARGET_DATA, icc_profile->data(), icc_profile->size())
            //     != JXL_DEC_SUCCESS)
            // {
            //     return Error("JxlDecoderGetColorAsICCProfile failed"s);
            // }
        }
        else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER)
        {
            JxlPixelFormat format
                = { channels, bit_depth == 8 ? JXL_TYPE_UINT8 : JXL_TYPE_UINT16, JXL_NATIVE_ENDIAN, 0 };

            size_t buffer_size;
            JXL_ENSURE_SUCCESS(JxlDecoderImageOutBufferSize, dec.get(), &format, &buffer_size);
            if (buffer_size != width * height * channels * bit_depth / 8)
            {
                // fprintf(stderr, "Invalid out buffer size %zu %zu\n", buffer_size, width * height * 16);
                return Error("Invalid out buffer size"_binary);
            }
            pixels = binary { buffer_size };
            JXL_ENSURE_SUCCESS(JxlDecoderSetImageOutBuffer, dec.get(), &format, pixels.data, pixels.size);
        }
        else if (status == JXL_DEC_FULL_IMAGE)
        {
            // Nothing to do. Do not yet return. If the image is an animation, more
            // full frames may be decoded. This example only keeps the last one.
        }
        else if (status == JXL_DEC_SUCCESS)
        {
            // All decoding successfully finished.
            // It's not required to call JxlDecoderReleaseInput(dec.get()) here since
            // the decoder will be destroyed.
            return Ok(make_tuple(std::move(pixels), width, height, channels, bit_depth));
        }
        else
        {
            return Error("Unknown decoder status"_binary);
        }
    }
}


erl_result<vector<uint8_t>, binary> jxl_compress(
    const binary& pixels,
    uint32_t width,
    uint32_t height,
    uint32_t channels,
    uint32_t bit_depth,
    double distance,
    bool lossless,
    int effort)
{
    static auto runner = JxlThreadParallelRunnerMake(
        /*memory_manager=*/nullptr, JxlThreadParallelRunnerDefaultNumWorkerThreads());

    auto enc = JxlEncoderMake(/*memory_manager=*/nullptr);
    JXL_ENSURE_SUCCESS(JxlEncoderSetParallelRunner, enc.get(), JxlThreadParallelRunner, runner.get());

    JxlPixelFormat pixel_format
        = { channels, bit_depth == 16 ? JXL_TYPE_UINT16 : JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0 };

    JxlBasicInfo basic_info = jxl_basic_info_from_pixel_format(pixel_format);
    basic_info.xsize = width;
    basic_info.ysize = height;
    basic_info.uses_original_profile = lossless;
    JXL_ENSURE_SUCCESS(JxlEncoderSetBasicInfo, enc.get(), &basic_info);

    JxlColorEncoding color_encoding = {};
    const bool is_grayscale = pixel_format.num_channels < 3;
    JxlColorEncodingSetToSRGB(&color_encoding, is_grayscale);
    JXL_ENSURE_SUCCESS(JxlEncoderSetColorEncoding, enc.get(), &color_encoding);

    auto encoder_options = JxlEncoderFrameSettingsCreate(enc.get(), nullptr);
    JXL_ENSURE_SUCCESS(JxlEncoderSetFrameLossless, encoder_options, lossless);
    JXL_ENSURE_SUCCESS(JxlEncoderSetFrameDistance, encoder_options, distance);
    JXL_ENSURE_SUCCESS(JxlEncoderFrameSettingsSetOption, encoder_options, JXL_ENC_FRAME_SETTING_EFFORT, effort);

    JXL_ENSURE_SUCCESS(JxlEncoderAddImageFrame, encoder_options, &pixel_format, pixels.data, pixels.size);
    JxlEncoderCloseInput(enc.get());

    vector<uint8_t> compressed(64);
    uint8_t* next_out = compressed.data();
    size_t avail_out = compressed.size() - (next_out - compressed.data());
    JxlEncoderStatus process_result;
    while (true)
    {
        process_result = JxlEncoderProcessOutput(enc.get(), &next_out, &avail_out);
        if (process_result != JXL_ENC_NEED_MORE_OUTPUT)
            break;
        size_t offset = next_out - compressed.data();
        compressed.resize(compressed.size() * 2);
        next_out = compressed.data() + offset;
        avail_out = compressed.size() - offset;
    }
    compressed.resize(next_out - compressed.data());
    if (process_result != JXL_ENC_SUCCESS)
    {
        printf("status: %d\n", process_result);
        return Error("JxlEncoderProcessOutput failed"_binary);
    }

    return Ok(std::move(compressed));
}


erl_result<vector<uint8_t>, binary> jxl_transcode_from_jpeg(const binary& jpeg_bytes, int effort)
{
    auto enc = JxlEncoderMake(/*memory_manager=*/nullptr);

    JXL_ENSURE_SUCCESS(JxlEncoderUseContainer, enc.get(), JXL_TRUE);
    JXL_ENSURE_SUCCESS(JxlEncoderStoreJPEGMetadata, enc.get(), JXL_TRUE);

    auto encoder_options = JxlEncoderFrameSettingsCreate(enc.get(), nullptr);
    JXL_ENSURE_SUCCESS(JxlEncoderFrameSettingsSetOption, encoder_options, JXL_ENC_FRAME_SETTING_EFFORT, effort);
    JXL_ENSURE_SUCCESS(JxlEncoderAddJPEGFrame, encoder_options, jpeg_bytes.data, jpeg_bytes.size);
    JxlEncoderCloseInput(enc.get());

    vector<uint8_t> compressed(64);
    uint8_t* next_out = compressed.data();
    size_t avail_out = compressed.size() - (next_out - compressed.data());
    JxlEncoderStatus process_result;
    while (true)
    {
        process_result = JxlEncoderProcessOutput(enc.get(), &next_out, &avail_out);
        if (process_result != JXL_ENC_NEED_MORE_OUTPUT)
            break;
        size_t offset = next_out - compressed.data();
        compressed.resize(compressed.size() * 2);
        next_out = compressed.data() + offset;
        avail_out = compressed.size() - offset;
    }
    compressed.resize(next_out - compressed.data());
    if (process_result != JXL_ENC_SUCCESS)
    {
        printf("status: %d\n", process_result);
        return Error("JxlEncoderProcessOutput failed"_binary);
    }

    return Ok(std::move(compressed));
}


struct TIFFWrapper
{
    TIFF* tiff;
    stringstream* sstream;

    ~TIFFWrapper()
    {
        TIFFClose(this->tiff);
        delete this->sstream;
    }
};


typedef resource<std::unique_ptr<poppler::document>> pdf_resource_t;
typedef resource<TIFFWrapper> tiff_resource_t;


erl_result<tuple<pdf_resource_t, int>, binary> pdf_load_document(binary bytes)
{
    // load document from bytes and check for errors
    vector<char> buf(bytes.data, bytes.data + bytes.size);
    poppler::document* document = poppler::document::load_from_data(&buf);
    if (!document)
        return Error("invalid pdf file"_binary);
    if (document->is_locked())
    {
        delete document;
        return Error("document is locked"_binary);
    }

    const auto num_pages = document->pages();
    return Ok(make_tuple(pdf_resource_t::alloc(document), num_pages));
}


erl_result<tuple<binary, uint32_t, uint32_t, uint32_t>, binary>
pdf_render_page(pdf_resource_t document_resource, int page_idx, int dpi)
{
    auto& document = document_resource.get();
    if (page_idx < 0 || page_idx >= document->pages())
        throw std::invalid_argument("page index out of range");

    unique_ptr<poppler::page> page(document->create_page(page_idx));
    poppler::page_renderer renderer;
    renderer.set_render_hints(
        poppler::page_renderer::antialiasing | poppler::page_renderer::text_antialiasing
        | poppler::page_renderer::text_hinting);
    auto image = renderer.render_page(page.get(), dpi, dpi);
    if (!image.is_valid())
        return Error("failed to render a valid image"_binary);

    uint32_t height = image.height();
    uint32_t width = image.width();
    binary pixels { height * image.bytes_per_row() };
    copy_n(image.data(), pixels.size, pixels.data);
    uint32_t channels = image.bytes_per_row() / width;

    const auto format = image.format();
    if (format == poppler::image::format_invalid)
        return Error("Invalid image format"_binary);
    else if (format == poppler::image::format_mono)
        return Error("Mono images not supported right now"_binary);
    else if (format == poppler::image::format_bgr24 || format == poppler::image::format_argb32)
    {
        // convert bgr to rgb
        for (uint32_t i = 0; i < pixels.size; i += channels)
            std::swap(pixels.data[i], pixels.data[i + 2]);
    }

    return Ok(make_tuple(move(pixels), width, height, channels));
}


erl_result<tuple<tiff_resource_t, int>, binary> tiff_load_document(binary bytes)
{
    // load document from bytes and check for errors
    auto sstream = new stringstream;
    sstream->write(reinterpret_cast<char*>(bytes.data), bytes.size);
    auto document = TIFFStreamOpen("file.tiff", reinterpret_cast<std::istream*>(sstream));
    if (!document)
        return Error("invalid tiff file"_binary);

    int num_pages = 0;
    do
    {
        num_pages++;
    } while (TIFFReadDirectory(document));

    return Ok(make_tuple(tiff_resource_t::alloc(document, sstream), num_pages));
}


erl_result<tuple<binary, uint32_t, uint32_t, uint32_t>, binary>
tiff_render_page(tiff_resource_t document_resource, int page_index)
{
    auto& [document, _] = document_resource.get();

    TIFFSetDirectory(document, page_index);

    int width, height;
    TIFFGetField(document, TIFFTAG_IMAGEWIDTH, &width);
    TIFFGetField(document, TIFFTAG_IMAGELENGTH, &height);

    binary pixels { static_cast<size_t>(width * height * 4) };
    TIFFReadRGBAImageOriented(document, width, height, reinterpret_cast<uint32_t*>(pixels.data), 1, 0);

    return Ok(make_tuple(std::move(pixels), static_cast<uint32_t>(width), static_cast<uint32_t>(height), 4u));
}


int load(ErlNifEnv* caller_env, void** priv_data, ERL_NIF_TERM load_info)
{
    pdf_resource_t::init(caller_env, "poppler");
    tiff_resource_t::init(caller_env, "tiff");
    yielding_resource_t::init(caller_env, "yielding_generator");
    TIFFSetWarningHandler(nullptr);

    return 0;
}


MODULE(
    Elixir.Imagex.C,
    load,
    nullptr,
    nullptr,
    def(jpeg_decompress, DirtyFlags::DirtyCpu),
    def(jpeg_compress, DirtyFlags::DirtyCpu),
    def(png_decompress, DirtyFlags::DirtyCpu),
    def(png_compress, DirtyFlags::DirtyCpu),
    def(jxl_decompress, DirtyFlags::DirtyCpu),
    def(jxl_compress, DirtyFlags::DirtyCpu),
    def(jxl_transcode_from_jpeg, DirtyFlags::DirtyCpu),
    def(pdf_load_document, DirtyFlags::DirtyCpu),
    def(pdf_render_page, DirtyFlags::DirtyCpu),
    def(tiff_load_document, DirtyFlags::DirtyCpu),
    def(tiff_render_page, DirtyFlags::DirtyCpu), )
