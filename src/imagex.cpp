#include "expp.hpp"
#include "jxl/decode.h"
#include "jxl/decode_cxx.h"
#include "stl.hpp"
#include <erl_nif.h>
#include <iostream>
#include <jpeglib.h>
#include <jxl/encode.h>
#include <jxl/encode_cxx.h>
#include <jxl/thread_parallel_runner.h>
#include <jxl/thread_parallel_runner_cxx.h>
#include <memory>
#include <png.h>
#include <stdio.h>
#include <tuple>
#include <vector>

using namespace std;


struct my_jpeg_error_mgr : jpeg_error_mgr
{
    jmp_buf setjmp_buffer;
};


void jpeg_error_exit(j_common_ptr cinfo)
{
    auto myerr = reinterpret_cast<my_jpeg_error_mgr*>(cinfo->err);
    longjmp(myerr->setjmp_buffer, 1);
}


erl_result<tuple<binary, uint32_t, uint32_t, uint32_t>, string> jpeg_decompress(const binary& jpeg_bytes) noexcept
{
    struct my_jpeg_error_mgr err;
    struct jpeg_decompress_struct cinfo;

    /* create decompressor */
    cinfo.err = jpeg_std_error(&err);
    jpeg_create_decompress(&cinfo);
    cinfo.do_fancy_upsampling = FALSE;
    err.error_exit = jpeg_error_exit;

    if (setjmp(err.setjmp_buffer))
    {
        char error_message[JMSG_LENGTH_MAX];
        (*(cinfo.err->format_message))(reinterpret_cast<j_common_ptr>(&cinfo), error_message);
        jpeg_destroy_decompress(&cinfo);
        return Error<string>(error_message);
    }

    /* set source buffer */
    jpeg_mem_src(&cinfo, jpeg_bytes.data, jpeg_bytes.size);

    /* read jpeg header */
    jpeg_read_header(&cinfo, TRUE);

    /* decompress */
    jpeg_start_decompress(&cinfo);
    unsigned output_bytes = cinfo.output_width * cinfo.output_height * cinfo.num_components;
    binary output(output_bytes);

    /* read scanlines */
    const auto row_stride = cinfo.output_width * cinfo.num_components;
    while (cinfo.output_scanline < cinfo.output_height)
    {
        auto row_ptr = output.data + cinfo.output_scanline * row_stride;
        jpeg_read_scanlines(&cinfo, &row_ptr, 1);
    }

    /* clean up */
    jpeg_finish_decompress(&cinfo);
    jpeg_destroy_decompress(&cinfo);
    return Ok(
        make_tuple(move(output), cinfo.output_width, cinfo.output_height, static_cast<uint32_t>(cinfo.num_components)));
}


erl_result<binary, string>
jpeg_compress(const binary& pixels, uint32_t width, uint32_t height, uint32_t channels, int quality)
{
    struct my_jpeg_error_mgr err;
    struct jpeg_compress_struct cinfo;

    // create the compressor
    cinfo.err = jpeg_std_error(&err);
    jpeg_create_compress(&cinfo);
    err.error_exit = jpeg_error_exit;

    if (setjmp(err.setjmp_buffer))
    {
        char error_message[JMSG_LENGTH_MAX];
        (*(cinfo.err->format_message))(reinterpret_cast<j_common_ptr>(&cinfo), error_message);
        jpeg_destroy_compress(&cinfo);
        return Error<string>(error_message);
    }

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
        auto row = pixels.data + cinfo.next_scanline * channels * width;
        jpeg_write_scanlines(&cinfo, &row, 1);
    }
    jpeg_finish_compress(&cinfo);
    jpeg_destroy_compress(&cinfo);

    // copy the buf to a binary objet
    binary out { size_t(outsize) };
    std::copy_n(buf, outsize, out.data);

    free(buf);  // free the buf created by jpeg_mem_dest

    return Ok(std::move(out));
}


struct png_read_binary
{
    const binary& data;
    size_t offset = 8;

    png_read_binary(const binary& data)
        : data(data)
    { }

    void read(png_bytep dest, png_size_t size_to_read)
    {
        std::copy_n(this->data.data + offset, size_to_read, dest);
        this->offset += size_to_read;
    }
};


erl_result<tuple<binary, uint32_t, uint32_t, uint32_t>, string> png_decompress(const binary& png_bytes) noexcept
{
    // check png signature
    if (png_sig_cmp(png_bytes.data, 0, 8))
        return Error("invalid png header"s);

    png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (!png_ptr)
        return Error("couldn't initialize png read struct"s);

    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr)
        return Error("couldn't initialize png info struct"s);

    if (setjmp(png_jmpbuf(png_ptr)))
    {
        png_destroy_read_struct(&png_ptr, &info_ptr, nullptr);
        return Error("An error has occured while reading the PNG file"s);
    }

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

    png_uint_32 width = png_get_image_width(png_ptr, info_ptr);
    png_uint_32 height = png_get_image_height(png_ptr, info_ptr);
    png_uint_32 bit_depth = png_get_bit_depth(png_ptr, info_ptr);
    png_uint_32 channels = png_get_channels(png_ptr, info_ptr);
    png_uint_32 color_type = png_get_color_type(png_ptr, info_ptr);

    switch (color_type)
    {
    case PNG_COLOR_TYPE_PALETTE:
        png_set_palette_to_rgb(png_ptr);
        channels = 3;
        break;
    case PNG_COLOR_TYPE_GRAY:
        if (bit_depth < 8)
            png_set_expand_gray_1_2_4_to_8(png_ptr);
        bit_depth = 8;
        break;
    }

    auto row_pointers = make_unique<png_bytep[]>(height);
    const unsigned int stride = width * bit_depth * channels / 8;
    binary output(height * stride);
    for (size_t i = 0; i < height; i++)
        row_pointers[i] = reinterpret_cast<png_bytep>(output.data) + i * stride;

    png_read_image(png_ptr, row_pointers.get());

    png_destroy_read_struct(&png_ptr, &info_ptr, nullptr);

    return Ok(make_tuple(std::move(output), width, height, channels));
}


erl_result<vector<png_byte>, string>
png_compress(const binary& pixels, uint32_t width, uint32_t height, uint32_t channels)
{
    png_structp png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (!png_ptr)
        return Error("couldn't initialize png write struct"s);

    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr)
        return Error("[write_png_file] png_create_info_struct failed"s);

    if (setjmp(png_jmpbuf(png_ptr)))
    {
        png_destroy_write_struct(&png_ptr, &info_ptr);
        return Error("[write_png_file] Error during init_io"s);
    }

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
    auto row_pointers = make_unique<png_bytep[]>(height);
    const unsigned int stride = width * channels;
    for (size_t i = 0; i < height; i++)
        row_pointers[i] = reinterpret_cast<png_bytep>(pixels.data + i * stride);
    png_write_image(png_ptr, row_pointers.get());

    // cleanup
    png_write_end(png_ptr, NULL);
    png_destroy_write_struct(&png_ptr, &info_ptr);

    return Ok(out_data);
}


erl_result<tuple<vector<uint8_t>, uint32_t, uint32_t, uint32_t>, string> jxl_decompress(const binary& jxl_bytes)
{
    // Multi-threaded parallel runner.
    auto runner = JxlThreadParallelRunnerMake(nullptr, JxlThreadParallelRunnerDefaultNumWorkerThreads());

    auto dec = JxlDecoderMake(nullptr);
    if (JxlDecoderSubscribeEvents(dec.get(), JXL_DEC_BASIC_INFO | JXL_DEC_COLOR_ENCODING | JXL_DEC_FULL_IMAGE)
        != JXL_DEC_SUCCESS)
    {
        return Error("JxlDecoderSubscribeEvents failed"s);
    }

    if (JxlDecoderSetParallelRunner(dec.get(), JxlThreadParallelRunner, runner.get()) != JXL_DEC_SUCCESS)
    {
        return Error("JxlDecoderSetParallelRunner failed"s);
    }

    JxlPixelFormat format = { 3, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0 };

    JxlDecoderSetInput(dec.get(), jxl_bytes.data, jxl_bytes.size);

    vector<uint8_t> pixels;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t channels = 0;

    for (;;)
    {
        JxlDecoderStatus status = JxlDecoderProcessInput(dec.get());

        if (status == JXL_DEC_ERROR)
        {
            return Error("Decoder error"s);
        }
        else if (status == JXL_DEC_NEED_MORE_INPUT)
        {
            return Error("Error, already provided all input"s);
        }
        else if (status == JXL_DEC_BASIC_INFO)
        {
            JxlBasicInfo info;
            if (JxlDecoderGetBasicInfo(dec.get(), &info) != JXL_DEC_SUCCESS)
            {
                return Error("JxlDecoderGetBasicInfo failed"s);
            }
            width = info.xsize;
            height = info.ysize;
            channels = info.num_color_channels + info.num_extra_channels;
        }
        else if (status == JXL_DEC_COLOR_ENCODING)
        {
            // Get the ICC color profile of the pixel data
            size_t icc_size;
            if (JxlDecoderGetICCProfileSize(dec.get(), &format, JXL_COLOR_PROFILE_TARGET_DATA, &icc_size)
                != JXL_DEC_SUCCESS)
            {
                return Error("JxlDecoderGetICCProfileSize failed"s);
            }
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
            size_t buffer_size;
            if (JxlDecoderImageOutBufferSize(dec.get(), &format, &buffer_size) != JXL_DEC_SUCCESS)
            {
                return Error("JxlDecoderImageOutBufferSize failed"s);
            }
            if (buffer_size != width * height * 3)
            {
                // fprintf(stderr, "Invalid out buffer size %zu %zu\n", buffer_size, width * height * 16);
                return Error("Invalid out buffer size"s);
            }
            pixels.resize(buffer_size);
            void* pixels_buffer = (void*)pixels.data();
            size_t pixels_buffer_size = pixels.size() * sizeof(uint8_t);
            if (JxlDecoderSetImageOutBuffer(dec.get(), &format, pixels_buffer, pixels_buffer_size) != JXL_DEC_SUCCESS)
            {
                return Error("JxlDecoderSetImageOutBuffer failed"s);
            }
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
            return Ok(make_tuple(std::move(pixels), width, height, channels));
        }
        else
        {
            return Error("Unknown decoder status"s);
        }
    }
}


erl_result<vector<uint8_t>, string>
jxl_compress(const binary& pixels, uint32_t width, uint32_t height, uint32_t channels, int lossless)
{
    auto enc = JxlEncoderMake(/*memory_manager=*/nullptr);
    auto runner = JxlThreadParallelRunnerMake(
        /*memory_manager=*/nullptr, JxlThreadParallelRunnerDefaultNumWorkerThreads());
    if (JxlEncoderSetParallelRunner(enc.get(), JxlThreadParallelRunner, runner.get()) != JXL_ENC_SUCCESS)
    {
        return Error("JxlEncoderSetParallelRunner failed"s);
    }

    JxlPixelFormat pixel_format = { channels, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0 };

    JxlBasicInfo basic_info = {};
    basic_info.xsize = width;
    basic_info.ysize = height;
    basic_info.bits_per_sample = 32;
    basic_info.exponent_bits_per_sample = 8;
    basic_info.alpha_exponent_bits = 0;
    basic_info.alpha_bits = 0;
    basic_info.uses_original_profile = JXL_FALSE;
    if (JxlEncoderSetBasicInfo(enc.get(), &basic_info) != JXL_ENC_SUCCESS)
    {
        return Error("JxlEncoderSetBasicInfo failed"s);
    }

    JxlColorEncoding color_encoding = {};
    JxlColorEncodingSetToSRGB(
        &color_encoding,
        /*is_gray=*/pixel_format.num_channels < 3);
    if (JxlEncoderSetColorEncoding(enc.get(), &color_encoding) != JXL_ENC_SUCCESS)
    {
        return Error("JxlEncoderSetColorEncoding failed"s);
    }

    auto encoder_options = JxlEncoderOptionsCreate(enc.get(), nullptr);

    JxlEncoderOptionsSetLossless(encoder_options, lossless);

    if (JxlEncoderAddImageFrame(
            encoder_options, &pixel_format, reinterpret_cast<void*>(pixels.data), sizeof(uint8_t) * pixels.size)
        != JXL_ENC_SUCCESS)
    {
        return Error("JxlEncoderAddImageFrame failed"s);
    }

    std::vector<uint8_t> compressed(64);
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
        return Error("JxlEncoderProcessOutput failed"s);

    return Ok(compressed);
}


MODULE(
    Elixir.Imagex,
    def(jpeg_decompress, "jpeg_decompress_impl", DirtyFlags::DirtyCpu),
    def(jpeg_compress, "jpeg_compress_impl", DirtyFlags::DirtyCpu),
    def(png_decompress, "png_decompress_impl", DirtyFlags::DirtyCpu),
    def(png_compress, "png_compress_impl", DirtyFlags::DirtyCpu),
    def(jxl_decompress, "jxl_decompress_impl", DirtyFlags::DirtyCpu),
    def(jxl_compress, "jxl_compress_impl", DirtyFlags::DirtyCpu), )
