#include <tuple>
#include <stdio.h>
#include <jpeglib.h>
#include <png.h>
#include <erl_nif.h>
#include <iostream>
#include "expp.hpp"
using namespace std;


tuple<blob, int, int, int> jpeg_decompress(const blob& jpeg_bytes)
{
    struct jpeg_error_mgr err;
    struct jpeg_decompress_struct cinfo;

    /* create decompressor */
    jpeg_create_decompress(&cinfo);
    cinfo.err = jpeg_std_error(&err);
    cinfo.do_fancy_upsampling = FALSE;
    err.error_exit = [](j_common_ptr cinfo) {
        char error_message[1024];
        (cinfo->err->format_message)(cinfo, error_message);
        throw erl_error<string>(error_message);
    };

    /* set source buffer */
    jpeg_mem_src(&cinfo, jpeg_bytes.data(), jpeg_bytes.size());

    /* read jpeg header */
    jpeg_read_header(&cinfo, TRUE);

    /* decompress */
    jpeg_start_decompress(&cinfo);
    unsigned output_bytes = cinfo.output_width * cinfo.output_height * cinfo.num_components;
    blob output(output_bytes);

    /* read scanlines */
    const auto row_stride = cinfo.output_width * cinfo.num_components;
    while (cinfo.output_scanline < cinfo.output_height)
    {
        auto row_ptr = output.data() + cinfo.output_scanline * row_stride;
        jpeg_read_scanlines(&cinfo, &row_ptr, 1);
    }   

    /* clean up */
    jpeg_finish_decompress(&cinfo);
    jpeg_destroy_decompress(&cinfo);
    return make_tuple(move(output), cinfo.output_width, cinfo.output_height, cinfo.num_components);
}


struct png_read_blob
{
    const blob& data;
    size_t offset = 8;

    png_read_blob(const blob& data) : data(data)
    {}

    void read(png_bytep dest, png_size_t size_to_read)
    {
        std::copy_n(this->data.data() + offset, size_to_read, dest);
        this->offset += size_to_read;
    }
};


tuple<blob, int, int, int> png_decompress(const blob& png_bytes)
{
    // check png signature
    if (png_sig_cmp(png_bytes.data(), 0, 8))
        throw erl_error<string>("invalid png header");

    png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (!png_ptr)
        throw erl_error<string>("couldn't initialize png read struct");

    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr)
        throw erl_error<string>("couldn't initialize png info struct");

    png_bytep* row_ptrs = nullptr;

    if (setjmp(png_jmpbuf(png_ptr)))
    {
        png_destroy_read_struct(&png_ptr, &info_ptr, nullptr);
        delete[] row_ptrs;
        throw erl_error<string>("An error has occured while reading the PNG file");
    }

    png_read_blob data_wrapper(png_bytes);
    png_set_read_fn(png_ptr, reinterpret_cast<png_voidp>(&data_wrapper), [](png_structp png_ptr, png_bytep dest, png_size_t size_to_read) {
        auto data_wrapper = reinterpret_cast<png_read_blob*>(png_get_io_ptr(png_ptr));
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

    row_ptrs = new png_bytep[height];
    const unsigned int stride = width * bit_depth * channels / 8;
    blob output(height * stride);
    for (size_t i = 0; i < height; i++)
        row_ptrs[i] = reinterpret_cast<png_bytep>(output.data()) + i * stride;

    png_read_image(png_ptr, row_ptrs);

    delete[] row_ptrs;
    png_destroy_read_struct(&png_ptr, &info_ptr, nullptr);

    return make_tuple(output, width, height, channels);
}


tuple<blob, int, int, int> decode(const blob& bytes)
{
    try
    {
        return jpeg_decompress(bytes);
    }
    catch (const erl_error<string>&)
    {}

    try
    {
        return png_decompress(bytes);
    }
    catch (const erl_error<string>&)
    {}

    throw erl_error<string>("failed to decode");
}



blob rgb2gray(const blob& bytes)
{
    blob output(bytes.size() / 3);
    auto input_bytes = bytes.data();
    auto output_bytes = output.data();

    for (unsigned i = 0, j = 0; i < bytes.size(); i += 3, j++)
    {
        output_bytes[j] = static_cast<unsigned char>(
            (
                input_bytes[i] * 299 +
                input_bytes[i+1] * 587 +
                input_bytes[i+2] * 114
            ) / 1000
        );
    }

    return output;
}


ELIXIR_MODULE(Imagex,
    def(jpeg_decompress, "jpeg_decompress"),
    def(png_decompress, "png_decompress"),
    def(decode, "decode"),
    def(rgb2gray, "rgb2gray"),
)
