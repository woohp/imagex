#include "expp.hpp"
#include <bit>
#include <cstring>
#include <erl_nif.h>
#include <jpeglib.h>
#include <jxl/decode.h>
#include <jxl/decode_cxx.h>
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
using namespace expp;

// pixels, width, height, channels, bit_depth, optional<exif>, optional<text_chunks>
typedef tuple<
    binary,
    uint32_t,
    uint32_t,
    uint32_t,
    uint32_t,
    optional<binary>,
    optional<std::vector<pair<binary, binary>>>>
    decompress_result_t;


// Named helper to construct decompress_result_t without positional mistakes.
inline decompress_result_t make_decompress_result(
    binary pixels,
    uint32_t width,
    uint32_t height,
    uint32_t channels,
    uint32_t bit_depth,
    optional<binary> exif = nullopt,
    optional<std::vector<pair<binary, binary>>> text_chunks = nullopt)
{
    return make_tuple(std::move(pixels), width, height, channels, bit_depth, std::move(exif), std::move(text_chunks));
}


// RAII guard for jpeg_decompress_struct.
struct jpeg_decompress_guard
{
    jpeg_decompress_struct* cinfo;
    explicit jpeg_decompress_guard(jpeg_decompress_struct* c)
        : cinfo(c)
    { }
    ~jpeg_decompress_guard()
    {
        if (cinfo)
            jpeg_destroy_decompress(cinfo);
    }
    jpeg_decompress_guard(const jpeg_decompress_guard&) = delete;
    jpeg_decompress_guard& operator=(const jpeg_decompress_guard&) = delete;
    void release()
    {
        cinfo = nullptr;
    }
};


// RAII guard for jpeg_compress_struct.
struct jpeg_compress_guard
{
    jpeg_compress_struct* cinfo;
    explicit jpeg_compress_guard(jpeg_compress_struct* c)
        : cinfo(c)
    { }
    ~jpeg_compress_guard()
    {
        if (cinfo)
            jpeg_destroy_compress(cinfo);
    }
    jpeg_compress_guard(const jpeg_compress_guard&) = delete;
    jpeg_compress_guard& operator=(const jpeg_compress_guard&) = delete;
    void release()
    {
        cinfo = nullptr;
    }
};


void jpeg_error_exit(j_common_ptr cinfo)
{
    char error_message[JMSG_LENGTH_MAX];
    (*(cinfo->err->format_message))(cinfo, error_message);
    throw erl_error<string>(error_message);
}


yielding<expected<decompress_result_t, string>> jpeg_decompress(std::vector<uint8_t> jpeg_bytes)
{
    struct jpeg_error_mgr err;
    struct jpeg_decompress_struct cinfo;
    jpeg_decompress_guard guard(&cinfo);
    yielding_timer timer;

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

    // Save dimensions before destroying the struct
    const uint32_t out_width = cinfo.output_width;
    const uint32_t out_height = cinfo.output_height;
    const uint32_t num_components = static_cast<uint32_t>(cinfo.num_components);

    unsigned output_bytes = out_width * out_height * num_components;
    binary output(output_bytes);

    // read scanlines
    const auto row_stride = out_width * num_components;
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
    guard.release();
    jpeg_destroy_decompress(&cinfo);

    co_yield make_decompress_result(std::move(output), out_width, out_height, num_components, 8u);
}


yielding<expected<binary, string>>
jpeg_compress(vector<uint8_t> pixels, uint32_t width, uint32_t height, uint32_t channels, int quality)
{
    struct jpeg_error_mgr err;
    struct jpeg_compress_struct cinfo;
    jpeg_compress_guard guard(&cinfo);
    yielding_timer timer;

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
    guard.release();
    jpeg_destroy_compress(&cinfo);

    // copy the buf to a binary object
    binary out = binary::from_bytes(buf, outsize);
    free(buf);  // free the buf created by jpeg_mem_dest

    co_yield std::move(out);
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


yielding<expected<decompress_result_t, string_view>> png_decompress(vector<uint8_t> png_bytes)
{
    yielding_timer timer;

    // check png signature
    if (png_sig_cmp(png_bytes.data(), 0, 8))
    {
        co_yield std::unexpected("invalid png header");
        co_return;
    }

    png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, nullptr, png_error_exit, nullptr);
    if (!png_ptr)
    {
        co_yield std::unexpected("couldn't initialize png read struct");
        co_return;
    }

    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr)
    {
        png_destroy_read_struct(&png_ptr, nullptr, nullptr);
        co_yield std::unexpected("couldn't initialize png info struct");
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
            break;
        }

        if constexpr (std::endian::native == std::endian::little)
        {
            if (bit_depth == 16)
                png_set_swap(png_ptr);
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

        // read the exif data
        optional<binary> exif_data = nullopt;
        {
            png_bytep exif = nullptr;
            png_uint_32 exif_length;
            if (png_get_eXIf_1(png_ptr, info_ptr, &exif_length, &exif) != 0)
            {
                if (exif_length > 0)
                    exif_data = binary::from_bytes(exif, exif_length);
            }
        }

        // read tEXt/iTxt/zTXt data
        optional<vector<pair<binary, binary>>> text_data = nullopt;
        {
            png_textp text_ptr = nullptr;
            if (int num_text = png_get_text(png_ptr, info_ptr, &text_ptr, nullptr); num_text > 0)
            {
                text_data = vector<pair<binary, binary>> { };

                for (int i = 0; i < num_text; i++)
                {
                    // TODO: handle iTxt/zTxt compressed text chunks
                    if (text_ptr[i].compression != PNG_TEXT_COMPRESSION_NONE)
                        continue;

                    binary key = binary::from_bytes(text_ptr[i].key, strlen(text_ptr[i].key));
                    binary text = binary::from_bytes(text_ptr[i].text, text_ptr[i].text_length);

                    text_data->push_back({ std::move(key), std::move(text) });
                }

                if (text_data->empty())
                    text_data = nullopt;
            }
        }

        png_destroy_read_struct(&png_ptr, &info_ptr, nullptr);
        png_ptr = nullptr;

        co_yield make_decompress_result(
            std::move(output), width, height, channels, bit_depth, std::move(exif_data), std::move(text_data));
    }
    catch (erl_error<string>& e)
    {
        if (png_ptr)
            png_destroy_read_struct(&png_ptr, &info_ptr, nullptr);
        throw e;
    }
}


yielding<expected<vector<png_byte>, string_view>>
png_compress(vector<uint8_t> pixels, uint32_t width, uint32_t height, uint32_t channels, uint32_t bit_depth)
{
    yielding_timer timer;

    if (channels == 0 || channels > 4)
    {
        co_yield std::unexpected("unsupported number of channels (must be 1-4)");
        co_return;
    }

    png_structp png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, nullptr, png_error_exit, nullptr);
    if (!png_ptr)
    {
        co_yield std::unexpected("couldn't initialize png write struct");
        co_return;
    }

    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr)
    {
        png_destroy_write_struct(&png_ptr, nullptr);
        co_yield std::unexpected("couldn't initialize png info struct");
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
        int color_type;
        switch (channels)
        {
        case 1:
            color_type = PNG_COLOR_TYPE_GRAY;
            break;
        case 2:
            color_type = PNG_COLOR_TYPE_GRAY_ALPHA;
            break;
        case 3:
            color_type = PNG_COLOR_TYPE_RGB;
            break;
        case 4:
            color_type = PNG_COLOR_TYPE_RGB_ALPHA;
            break;
        default:
            __builtin_unreachable();  // validated above
        }

        png_set_IHDR(
            png_ptr,
            info_ptr,
            width,
            height,
            bit_depth,
            color_type,
            PNG_INTERLACE_NONE,
            PNG_COMPRESSION_TYPE_BASE,
            PNG_FILTER_TYPE_BASE);
        png_write_info(png_ptr, info_ptr);

        if constexpr (std::endian::native == std::endian::little)
        {
            if (bit_depth == 16)
                png_set_swap(png_ptr);
        }

        // write the pixels
        const unsigned int stride = width * channels * bit_depth / 8;
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

        co_yield std::move(out_data);
    }
    catch (erl_error<string>& e)
    {
        if (png_ptr)
            png_destroy_write_struct(&png_ptr, &info_ptr);
        throw e;
    }
}


static_assert(JXL_ENC_SUCCESS == 0 && JXL_DEC_SUCCESS == 0);

// NOTE: This macro uses `return`, NOT `co_return`. It is NOT safe to use inside coroutines.
#define JXL_ENSURE_SUCCESS(func, ...)                                                                                  \
    if (func(__VA_ARGS__) != 0)                                                                                        \
    {                                                                                                                  \
        return std::unexpected(#func " failed");                                                                       \
    }


// Parse JXL EXIF box data, handling the 4-byte big-endian offset prefix.
// Consumes the remaining box buffer via JxlDecoderReleaseBoxBuffer.
static optional<binary> parse_jxl_exif(std::vector<uint8_t>& exif_data, JxlDecoder* dec)
{
    size_t remaining = JxlDecoderReleaseBoxBuffer(dec);
    exif_data.resize(exif_data.size() - remaining);

    if (exif_data.size() < 4)
        return nullopt;

    // The first 4 bytes are a big-endian offset (usually 0)
    size_t offset = static_cast<size_t>(exif_data[0]) << 24 | static_cast<size_t>(exif_data[1]) << 16
        | static_cast<size_t>(exif_data[2]) << 8 | static_cast<size_t>(exif_data[3]);

    if (4 + offset >= exif_data.size())
        return nullopt;

    return binary::from_bytes(exif_data.data() + 4 + offset, exif_data.size() - 4 - offset);
}


// Collect all output from a JXL encoder into a vector.
static expected<vector<uint8_t>, string_view> jxl_collect_compressed(JxlEncoder* enc)
{
    vector<uint8_t> compressed(64);
    uint8_t* next_out = compressed.data();
    size_t avail_out = compressed.size();
    JxlEncoderStatus process_result;
    while (true)
    {
        process_result = JxlEncoderProcessOutput(enc, &next_out, &avail_out);
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
        fprintf(stderr, "JxlEncoderProcessOutput failed with status: %d\n", process_result);
        return std::unexpected("JxlEncoderProcessOutput failed");
    }

    return compressed;
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

    if (pixel_format.num_channels < 3)
        basic_info.num_color_channels = 1;
    else
        basic_info.num_color_channels = 3;

    if (pixel_format.num_channels == 2 || pixel_format.num_channels == 4)
    {
        basic_info.alpha_exponent_bits = basic_info.exponent_bits_per_sample;
        basic_info.alpha_bits = basic_info.bits_per_sample;
        basic_info.num_extra_channels = 1;
    }
    else
    {
        basic_info.alpha_exponent_bits = 0;
        basic_info.alpha_bits = 0;
    }

    return basic_info;
}


expected<decompress_result_t, string_view> jxl_decompress(const binary& jxl_bytes)
{
    // Multi-threaded parallel runner.
    static auto runner = JxlResizableParallelRunnerMake(nullptr);

    auto dec = JxlDecoderMake(nullptr);
    JXL_ENSURE_SUCCESS(
        JxlDecoderSubscribeEvents,
        dec.get(),
        JXL_DEC_BASIC_INFO | JXL_DEC_COLOR_ENCODING | JXL_DEC_FULL_IMAGE | JXL_DEC_BOX);
    JXL_ENSURE_SUCCESS(JxlDecoderSetParallelRunner, dec.get(), JxlResizableParallelRunner, runner.get());
    JXL_ENSURE_SUCCESS(JxlDecoderSetDecompressBoxes, dec.get(), JXL_TRUE);

    JXL_ENSURE_SUCCESS(JxlDecoderSetInput, dec.get(), jxl_bytes.data, jxl_bytes.size);

    binary pixels;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t channels = 0;
    uint32_t bit_depth = 0;
    uint32_t exponent_bits_per_sample = 0;

    const constexpr size_t chunk_size = 0xffff;
    std::vector<uint8_t> exif_data;

    int need_more_input_retries = 0;
    const int max_need_more_input_retries = 3;

    for (;;)
    {
        JxlDecoderStatus status = JxlDecoderProcessInput(dec.get());

        if (status == JXL_DEC_ERROR)
        {
            return std::unexpected("Decoder error");
        }
        else if (status == JXL_DEC_NEED_MORE_INPUT)
        {
            if (++need_more_input_retries > max_need_more_input_retries)
                return std::unexpected("Decoder requested more input but all input was already provided");
            JxlDecoderReleaseInput(dec.get());
            JxlDecoderSetInput(dec.get(), jxl_bytes.data, jxl_bytes.size);
        }
        else if (status == JXL_DEC_BASIC_INFO)
        {
            JxlBasicInfo info;
            JXL_ENSURE_SUCCESS(JxlDecoderGetBasicInfo, dec.get(), &info);

            if (info.exponent_bits_per_sample != 0)
                return std::unexpected("FLOAT32 images are currently not yet supported");

            width = info.xsize;
            height = info.ysize;
            channels = info.num_color_channels + info.num_extra_channels;
            bit_depth = info.bits_per_sample;
            exponent_bits_per_sample = info.exponent_bits_per_sample;
        }
        else if (status == JXL_DEC_COLOR_ENCODING)
        {
            // Color encoding event received; no action needed.
        }
        else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER)
        {
            JxlDataType data_type;
            if (bit_depth == 8)
                data_type = JXL_TYPE_UINT8;
            else if (bit_depth == 16)
            {
                if (exponent_bits_per_sample > 0)
                    data_type = JXL_TYPE_FLOAT;  // should be float16, but we're not going to worry about that for now
                else
                    data_type = JXL_TYPE_UINT16;
            }
            else if (bit_depth == 32)
                data_type = JXL_TYPE_FLOAT;
            else
                return std::unexpected("unrecognized bit depth");
            JxlPixelFormat format = { channels, data_type, JXL_NATIVE_ENDIAN, 0 };

            size_t buffer_size;
            JXL_ENSURE_SUCCESS(JxlDecoderImageOutBufferSize, dec.get(), &format, &buffer_size);
            if (buffer_size != width * height * channels * bit_depth / 8)
                return std::unexpected("Invalid out buffer size");
            pixels = binary { buffer_size };
            JXL_ENSURE_SUCCESS(JxlDecoderSetImageOutBuffer, dec.get(), &format, pixels.data, pixels.size);
        }
        else if (status == JXL_DEC_FULL_IMAGE)
        {
            // Nothing to do. Do not yet return. If the image is an animation, more
            // full frames may be decoded. This example only keeps the last one.
        }
        else if (status == JXL_DEC_BOX)
        {
            JxlBoxType box_type;
            JXL_ENSURE_SUCCESS(JxlDecoderGetBoxType, dec.get(), box_type, JXL_TRUE);
            if (string_view(box_type, std::size(box_type)) != "Exif")
                continue;

            exif_data.resize(chunk_size);
            JxlDecoderSetBoxBuffer(dec.get(), exif_data.data(), exif_data.size());
        }
        else if (status == JXL_DEC_BOX_NEED_MORE_OUTPUT)
        {
            const size_t remaining = JxlDecoderReleaseBoxBuffer(dec.get());
            const size_t output_pos = exif_data.size() - remaining;
            exif_data.resize(exif_data.size() + chunk_size);
            JXL_ENSURE_SUCCESS(
                JxlDecoderSetBoxBuffer, dec.get(), exif_data.data() + output_pos, exif_data.size() - output_pos);
        }
        else if (status == JXL_DEC_SUCCESS)
        {
            optional<binary> exif_data_final = nullopt;
            if (!exif_data.empty())
                exif_data_final = parse_jxl_exif(exif_data, dec.get());

            return make_decompress_result(
                std::move(pixels), width, height, channels, bit_depth, std::move(exif_data_final));
        }
        else
        {
            return std::unexpected("Unknown decoder status");
        }
    }
}


expected<optional<binary>, string_view> jxl_read_exif(const binary& bytes)
{
    // Multi-threaded parallel runner.
    static auto runner = JxlResizableParallelRunnerMake(nullptr);

    auto dec = JxlDecoderMake(nullptr);
    JXL_ENSURE_SUCCESS(JxlDecoderSubscribeEvents, dec.get(), JXL_DEC_BASIC_INFO | JXL_DEC_BOX);
    JXL_ENSURE_SUCCESS(JxlDecoderSetParallelRunner, dec.get(), JxlResizableParallelRunner, runner.get());
    JXL_ENSURE_SUCCESS(JxlDecoderSetDecompressBoxes, dec.get(), JXL_TRUE);

    JXL_ENSURE_SUCCESS(JxlDecoderSetInput, dec.get(), bytes.data, bytes.size);

    const constexpr size_t chunk_size = 0xffff;
    std::vector<uint8_t> exif_data;

    for (;;)
    {
        JxlDecoderStatus status = JxlDecoderProcessInput(dec.get());

        if (status == JXL_DEC_ERROR)
        {
            return std::unexpected("Decoder error");
        }
        else if (status == JXL_DEC_NEED_MORE_INPUT)
        {
            return std::unexpected("Error, already provided all input");
        }
        else if (status == JXL_DEC_BASIC_INFO)
        { }
        else if (status == JXL_DEC_BOX)
        {
            if (!exif_data.empty())
                break;

            JxlBoxType box_type;
            JXL_ENSURE_SUCCESS(JxlDecoderGetBoxType, dec.get(), box_type, JXL_TRUE);
            if (string_view(box_type, std::size(box_type)) != "Exif")
                continue;

            exif_data.resize(chunk_size);
            JxlDecoderSetBoxBuffer(dec.get(), exif_data.data(), exif_data.size());
        }
        else if (status == JXL_DEC_BOX_NEED_MORE_OUTPUT)
        {
            const size_t remaining = JxlDecoderReleaseBoxBuffer(dec.get());
            const size_t output_pos = exif_data.size() - remaining;
            exif_data.resize(exif_data.size() + chunk_size);
            JXL_ENSURE_SUCCESS(
                JxlDecoderSetBoxBuffer, dec.get(), exif_data.data() + output_pos, exif_data.size() - output_pos);
        }
        else if (status == JXL_DEC_SUCCESS)
        {
            break;
        }
        else
        {
            return std::unexpected("Unknown decoder status");
        }
    }

    if (!exif_data.empty())
        return parse_jxl_exif(exif_data, dec.get());

    return nullopt;
}


expected<vector<uint8_t>, string_view> jxl_compress(
    const binary& pixels,
    uint32_t width,
    uint32_t height,
    uint32_t channels,
    uint32_t bit_depth,
    double distance,
    bool lossless,
    int effort,
    int progressive,
    int order)
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

    JxlColorEncoding color_encoding = { };
    const bool is_grayscale = pixel_format.num_channels < 3;
    JxlColorEncodingSetToSRGB(&color_encoding, is_grayscale);
    JXL_ENSURE_SUCCESS(JxlEncoderSetColorEncoding, enc.get(), &color_encoding);

    auto encoder_options = JxlEncoderFrameSettingsCreate(enc.get(), nullptr);
    JXL_ENSURE_SUCCESS(JxlEncoderSetFrameLossless, encoder_options, lossless);
    JXL_ENSURE_SUCCESS(JxlEncoderSetFrameDistance, encoder_options, distance);
    JXL_ENSURE_SUCCESS(JxlEncoderFrameSettingsSetOption, encoder_options, JXL_ENC_FRAME_SETTING_EFFORT, effort);

    if (progressive > 0)
    {
        JXL_ENSURE_SUCCESS(
            JxlEncoderFrameSettingsSetOption, encoder_options, JXL_ENC_FRAME_SETTING_PROGRESSIVE_DC, progressive);
        JXL_ENSURE_SUCCESS(JxlEncoderFrameSettingsSetOption, encoder_options, JXL_ENC_FRAME_SETTING_PROGRESSIVE_AC, 1);
    }

    if (order > 0)
    {
        JXL_ENSURE_SUCCESS(JxlEncoderFrameSettingsSetOption, encoder_options, JXL_ENC_FRAME_SETTING_GROUP_ORDER, order);
    }

    JXL_ENSURE_SUCCESS(JxlEncoderAddImageFrame, encoder_options, &pixel_format, pixels.data, pixels.size);
    JxlEncoderCloseInput(enc.get());

    return jxl_collect_compressed(enc.get());
}


expected<vector<uint8_t>, string_view>
jxl_transcode_from_jpeg(const binary& jpeg_bytes, int effort, int store_jpeg_metadata)
{
    auto enc = JxlEncoderMake(/*memory_manager=*/nullptr);

    JXL_ENSURE_SUCCESS(JxlEncoderUseContainer, enc.get(), JXL_TRUE);
    JXL_ENSURE_SUCCESS(JxlEncoderStoreJPEGMetadata, enc.get(), JXL_TRUE);

    auto encoder_options = JxlEncoderFrameSettingsCreate(enc.get(), nullptr);
    JXL_ENSURE_SUCCESS(JxlEncoderStoreJPEGMetadata, enc.get(), store_jpeg_metadata);
    JXL_ENSURE_SUCCESS(JxlEncoderFrameSettingsSetOption, encoder_options, JXL_ENC_FRAME_SETTING_EFFORT, effort);
    JXL_ENSURE_SUCCESS(JxlEncoderAddJPEGFrame, encoder_options, jpeg_bytes.data, jpeg_bytes.size);
    JxlEncoderCloseInput(enc.get());

    return jxl_collect_compressed(enc.get());
}


expected<vector<uint8_t>, string_view> jxl_transcode_to_jpeg(const binary& jxl_bytes)
{
    // Multi-threaded parallel runner.
    static auto runner = JxlResizableParallelRunnerMake(nullptr);

    auto dec = JxlDecoderMake(nullptr);
    JXL_ENSURE_SUCCESS(JxlDecoderSubscribeEvents, dec.get(), JXL_DEC_FULL_IMAGE | JXL_DEC_JPEG_RECONSTRUCTION);
    JXL_ENSURE_SUCCESS(JxlDecoderSetParallelRunner, dec.get(), JxlResizableParallelRunner, runner.get());

    JxlDecoderSetInput(dec.get(), jxl_bytes.data, jxl_bytes.size);

    vector<uint8_t> jpeg_bytes;

    for (;;)
    {
        JxlDecoderStatus status = JxlDecoderProcessInput(dec.get());

        if (status == JXL_DEC_ERROR)
        {
            return std::unexpected("Decoder error");
        }
        else if (status == JXL_DEC_NEED_MORE_INPUT)
        {
            return std::unexpected("Error, already provided all input");
        }
        else if (status == JXL_DEC_JPEG_RECONSTRUCTION)
        {
            jpeg_bytes.resize(static_cast<size_t>(jxl_bytes.size * 1.5));
            JxlDecoderSetJPEGBuffer(dec.get(), jpeg_bytes.data(), jpeg_bytes.size());
        }
        else if (status == JXL_DEC_JPEG_NEED_MORE_OUTPUT)
        {
            const size_t existing_size = jpeg_bytes.size();
            jpeg_bytes.resize(static_cast<size_t>(existing_size * 1.5));
            const size_t bytes_unwritten = JxlDecoderReleaseJPEGBuffer(dec.get());
            const size_t bytes_already_written = existing_size - bytes_unwritten;
            if (bytes_already_written != 0)
                return std::unexpected("JXL JPEG transcode: unexpected partial write after buffer resize");
            JxlDecoderSetJPEGBuffer(dec.get(), jpeg_bytes.data(), jpeg_bytes.size());
        }
        else if (status == JXL_DEC_FULL_IMAGE)
        {
            // resize the vector back to the written size
            const size_t bytes_unwritten = JxlDecoderReleaseJPEGBuffer(dec.get());
            jpeg_bytes.resize(jpeg_bytes.size() - bytes_unwritten);
        }
        else if (status == JXL_DEC_SUCCESS)
        {
            // All decoding successfully finished.
            return jpeg_bytes;
        }
        else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER)
        {
            return std::unexpected("Cannot transcode to JPEG: image was not originally transcoded from JPEG");
        }
        else
        {
            return std::unexpected("Unknown decoder status");
        }
    }
}


struct TIFFWrapper
{
    TIFF* tiff;
    unique_ptr<stringstream> sstream;

    TIFFWrapper(TIFF* tiff, unique_ptr<stringstream> sstream)
        : tiff(tiff)
        , sstream(std::move(sstream))
    { }

    ~TIFFWrapper()
    {
        TIFFClose(this->tiff);
    }
};


typedef resource<std::unique_ptr<poppler::document>> pdf_resource_t;


expected<tuple<pdf_resource_t, int>, string_view> pdf_load_document(binary bytes)
{
    // load document from bytes and check for errors
    vector<char> buf(bytes.data, bytes.data + bytes.size);
    unique_ptr<poppler::document> document(poppler::document::load_from_data(&buf));
    if (!document)
        return std::unexpected("invalid pdf file");
    if (document->is_locked())
        return std::unexpected("document is locked");

    const auto num_pages = document->pages();
    return make_tuple(pdf_resource_t::alloc(std::move(document)), num_pages);
}


expected<decompress_result_t, string_view> pdf_render_page(pdf_resource_t document_resource, int page_idx, int dpi)
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
        return std::unexpected("failed to render a valid image");

    uint32_t height = image.height();
    uint32_t width = image.width();
    binary pixels = binary::from_bytes(image.data(), height * image.bytes_per_row());
    uint32_t channels = image.bytes_per_row() / width;

    const auto format = image.format();
    if (format == poppler::image::format_invalid)
        return std::unexpected("Invalid image format");
    else if (format == poppler::image::format_mono)
        return std::unexpected("Mono images not supported right now");
    else if (format == poppler::image::format_bgr24 || format == poppler::image::format_argb32)
    {
        // convert bgr to rgb
        for (uint32_t i = 0; i < pixels.size; i += channels)
            std::swap(pixels.data[i], pixels.data[i + 2]);
    }

    return make_decompress_result(std::move(pixels), width, height, channels, 8u);
}

typedef resource<TIFFWrapper> tiff_resource_t;

expected<tuple<tiff_resource_t, int>, string_view> tiff_load_document(binary bytes)
{
    // load document from bytes and check for errors
    auto sstream = make_unique<stringstream>();
    sstream->write(reinterpret_cast<char*>(bytes.data), bytes.size);
    auto document = TIFFStreamOpen("file.tiff", reinterpret_cast<std::istream*>(sstream.get()));
    if (!document)
        return std::unexpected("invalid tiff file");

    int num_pages = 0;
    do
    {
        num_pages++;
    } while (TIFFReadDirectory(document));

    return make_tuple(tiff_resource_t::alloc(document, std::move(sstream)), num_pages);
}


expected<decompress_result_t, string_view> tiff_render_page(tiff_resource_t document_resource, int page_index)
{
    auto& [document, _] = document_resource.get();

    if (!TIFFSetDirectory(document, page_index))
        return std::unexpected("failed to set TIFF directory");

    int width = 0, height = 0;
    if (!TIFFGetField(document, TIFFTAG_IMAGEWIDTH, &width))
        return std::unexpected("failed to read TIFF image width");
    if (!TIFFGetField(document, TIFFTAG_IMAGELENGTH, &height))
        return std::unexpected("failed to read TIFF image height");
    if (width <= 0 || height <= 0)
        return std::unexpected("invalid TIFF image dimensions");

    binary pixels { static_cast<size_t>(width * height * 4) };
    TIFFReadRGBAImageOriented(document, width, height, reinterpret_cast<uint32_t*>(pixels.data), 1, 0);

    return make_decompress_result(
        std::move(pixels), static_cast<uint32_t>(width), static_cast<uint32_t>(height), 4u, 8u);
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
    def(jxl_read_exif, DirtyFlags::DirtyCpu),
    def(jxl_compress, DirtyFlags::DirtyCpu),
    def(jxl_transcode_from_jpeg, DirtyFlags::DirtyCpu),
    def(jxl_transcode_to_jpeg, DirtyFlags::DirtyCpu),
    def(pdf_load_document, DirtyFlags::DirtyCpu),
    def(pdf_render_page, DirtyFlags::DirtyCpu),
    def(tiff_load_document, DirtyFlags::DirtyCpu),
    def(tiff_render_page, DirtyFlags::DirtyCpu), )
