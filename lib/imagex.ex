defmodule Imagex do
  @moduledoc """
  Documentation for Imagex.
  """

  @on_load :init

  app = Mix.Project.config[:app]

  def init do
    path = :filename.join(:code.priv_dir(unquote(app)), 'imagex')
    :ok = :erlang.load_nif(path, 0)
  end

  def jpeg_decompress(_bytes) do
    exit(:nif_library_not_loaded)
  end

  def rgb2gray(_pixels) do
    exit(:nif_library_not_loaded)
  end
end
