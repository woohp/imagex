#include <tuple>
#include <stdio.h>
#include <jpeglib.h>
#include <erl_nif.h>
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
    return tuple(move(output), cinfo.output_width, cinfo.output_height, cinfo.num_components);
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
    def(rgb2gray, "rgb2gray"),
)
