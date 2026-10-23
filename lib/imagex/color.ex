defmodule Imagex.Color do
  @moduledoc false

  @doc """
  Converts a tensor from one colorspace to another. Removing alpha composites onto black, and grayscale output has
  shape `{height, width}`.
  """
  def convert(tensor, from, to) do
    {height, width} = {elem(tensor.shape, 0), elem(tensor.shape, 1)}
    {color, alpha} = tensor |> Nx.reshape({height, width, :auto}) |> split_alpha(from)
    color = if alpha != nil and to in [:L, :RGB], do: composite_onto_black(color, alpha), else: color

    color =
      case {from in [:L, :LA], to in [:L, :LA]} do
        {true, false} -> Nx.tile(color, [1, 1, 3])
        {false, true} -> to_grayscale(color)
        _same -> color
      end

    case to do
      :L -> Nx.reshape(color, {height, width})
      :RGB -> color
      _with_alpha -> Nx.concatenate([color, alpha || opaque(color)], axis: 2)
    end
  end

  defp split_alpha(tensor, from) when from in [:LA, :RGBA] do
    {_height, _width, channels} = tensor.shape
    {Nx.slice_along_axis(tensor, 0, channels - 1, axis: 2), Nx.slice_along_axis(tensor, channels - 1, 1, axis: 2)}
  end

  defp split_alpha(tensor, _from), do: {tensor, nil}

  defp composite_onto_black(color, alpha) do
    alpha = Nx.divide(Nx.as_type(alpha, {:f, 32}), max_value(alpha.type))
    color |> Nx.as_type({:f, 32}) |> Nx.multiply(alpha) |> as_type(color.type)
  end

  # L = 0.299R + 0.587G + 0.114B
  defp to_grayscale(rgb) do
    rgb
    |> Nx.as_type({:f, 32})
    |> Nx.dot(Nx.tensor([0.299, 0.587, 0.114], type: {:f, 32}))
    |> Nx.new_axis(-1)
    |> as_type(rgb.type)
  end

  defp opaque(%{shape: {height, width, _}, type: type}),
    do: Nx.broadcast(Nx.tensor(max_value(type), type: type), {height, width, 1})

  # Rounds to the nearest value when converting back to an integer type.
  defp as_type(tensor, {:f, _} = type), do: Nx.as_type(tensor, type)
  defp as_type(tensor, type), do: tensor |> Nx.round() |> Nx.as_type(type)

  defp max_value({:u, bits}), do: 2 ** bits - 1
  defp max_value({:s, bits}), do: 2 ** (bits - 1) - 1
  defp max_value({:f, _bits}), do: 1.0
end
