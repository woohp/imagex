#include "expp.hpp"
#include <erl_nif.h>
#include <iostream>
#include <jpeglib.h>
#include <memory>
#include <png.h>
#include <stdio.h>
#include <tuple>
using namespace std;

struct my_jpeg_error_mgr : jpeg_error_mgr
{
    jmp_buf setjmp_buffer;
};

erl_result<tuple<binary, uint32_t, uint32_t, uint32_t>, string> jpeg_decompress(const binary& jpeg_bytes) noexcept
{
    struct my_jpeg_error_mgr err;
    struct jpeg_decompress_struct cinfo;

    /* create decompressor */
    jpeg_create_decompress(&cinfo);
    cinfo.err = jpeg_std_error(&err);
    cinfo.do_fancy_upsampling = FALSE;
    err.error_exit = [](j_common_ptr cinfo) {
        auto myerr = reinterpret_cast<my_jpeg_error_mgr*>(cinfo->err);
        longjmp(myerr->setjmp_buffer, 1);
    };

    if (setjmp(err.setjmp_buffer))
    {
        jpeg_destroy_decompress(&cinfo);
        char error_message[JMSG_LENGTH_MAX];
        (*(cinfo.err->format_message))(reinterpret_cast<j_common_ptr>(&cinfo), error_message);
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

    auto row_ptrs = make_unique<png_bytep[]>(height);
    const unsigned int stride = width * bit_depth * channels / 8;
    binary output(height * stride);
    for (size_t i = 0; i < height; i++)
        row_ptrs[i] = reinterpret_cast<png_bytep>(output.data) + i * stride;

    png_read_image(png_ptr, row_ptrs.get());

    png_destroy_read_struct(&png_ptr, &info_ptr, nullptr);

    return Ok(make_tuple(output, width, height, channels));
}

erl_result<tuple<binary, uint32_t, uint32_t, uint32_t>, string> decode(const binary& bytes) noexcept
{
    {
        auto out = jpeg_decompress(bytes);
        if (out.ok())
            return out;
    }

    {
        auto out = png_decompress(bytes);
        if (out.ok())
            return out;
    }

    return Error("failed to decode"s);
}

binary rgb2gray(const binary& bytes)
{
    binary output(bytes.size / 3);
    auto input_bytes = bytes.data;
    auto output_bytes = output.data;

    for (unsigned i = 0, j = 0; i < bytes.size; i += 3, j++)
    {
        output_bytes[j] = static_cast<unsigned char>(
            (input_bytes[i] * 299 + input_bytes[i + 1] * 587 + input_bytes[i + 2] * 114) / 1000);
    }

    return output;
}

MODULE(
    Elixir.Imagex,
    def(jpeg_decompress),
    def(png_decompress),
    def(decode),
    def(rgb2gray), )
