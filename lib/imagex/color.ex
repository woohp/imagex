defmodule Imagex.Color do
  @moduledoc """
  Provides functions for colorspace conversion using Nx tensors.
  """

  @type colorspace :: :L | :LA | :RGB | :RGBA

  @doc """
  Converts a tensor from one colorspace to another.
  """
  def convert(tensor, from, to) do
    case {from, to} do
      {c, c} ->
        tensor

      {:L, :RGB} ->
        grayscale_to_rgb(tensor)

      {:L, :RGBA} ->
        tensor |> grayscale_to_rgb() |> add_alpha()

      {:L, :LA} ->
        add_alpha(tensor)

      {:LA, :L} ->
        merge_alpha_onto_black(tensor)

      {:LA, :RGB} ->
        tensor |> merge_alpha_onto_black() |> grayscale_to_rgb()

      {:LA, :RGBA} ->
        grayscale_alpha_to_rgba(tensor)

      {:RGB, :L} ->
        rgb_to_grayscale(tensor)

      {:RGB, :LA} ->
        tensor |> rgb_to_grayscale() |> add_alpha()

      {:RGB, :RGBA} ->
        add_alpha(tensor)

      {:RGBA, :L} ->
        tensor |> merge_alpha_onto_black() |> rgb_to_grayscale()

      {:RGBA, :LA} ->
        rgba_to_grayscale_alpha(tensor)

      {:RGBA, :RGB} ->
        merge_alpha_onto_black(tensor)
    end
  end

  defp grayscale_to_rgb(tensor) do
    # Broadcast 1 channel to 3 channels along the last dimension
    # If shape is {H, W}, reshape to {H, W, 1} first
    tensor = ensure_3d(tensor)
    Nx.tile(tensor, [1, 1, 3])
  end

  defp rgb_to_grayscale(tensor) do
    # L = 0.299R + 0.587G + 0.114B
    weights = Nx.tensor([0.299, 0.587, 0.114], type: {:f, 32})
    {height, width, _} = tensor.shape

    tensor
    |> Nx.as_type({:f, 32})
    |> Nx.reshape({height * width, 3})
    |> Nx.dot(weights)
    |> Nx.round()
    |> Nx.reshape({height, width, 1})
    |> Nx.as_type(tensor.type)
  end

  defp grayscale_alpha_to_rgba(tensor) do
    # {H, W, 2} -> {H, W, 4}
    # L, A -> L, L, L, A
    {height, width, _} = tensor.shape
    l = Nx.slice(tensor, [0, 0, 0], [height, width, 1])
    alpha = Nx.slice(tensor, [0, 0, 1], [height, width, 1])
    rgb = Nx.tile(l, [1, 1, 3])
    Nx.concatenate([rgb, alpha], axis: 2)
  end

  defp rgba_to_grayscale_alpha(tensor) do
    # {H, W, 4} -> {H, W, 2}
    # RGB, A -> L, A
    {height, width, _} = tensor.shape
    rgb = Nx.slice(tensor, [0, 0, 0], [height, width, 3])
    alpha = Nx.slice(tensor, [0, 0, 3], [height, width, 1])
    l = rgb_to_grayscale(rgb)
    Nx.concatenate([l, alpha], axis: 2)
  end

  defp add_alpha(tensor) do
    tensor = ensure_3d(tensor)
    {height, width, _} = tensor.shape
    max_val = max_channel_value(tensor.type)
    alpha = Nx.broadcast(Nx.tensor(max_val, type: tensor.type), {height, width, 1})
    Nx.concatenate([tensor, alpha], axis: 2)
  end

  defp merge_alpha_onto_black(tensor) do
    {height, width, channels} = tensor.shape
    color_channels = channels - 1

    color = Nx.slice(tensor, [0, 0, 0], [height, width, color_channels])
    alpha = Nx.slice(tensor, [0, 0, color_channels], [height, width, 1])

    max_val = max_channel_value(tensor.type)

    color_f = Nx.as_type(color, {:f, 32})
    alpha_f = Nx.divide(Nx.as_type(alpha, {:f, 32}), max_val)

    # Composite onto black: C_out = C_src * alpha_src + C_bg * (1 - alpha_src)
    # Since C_bg = 0, C_out = C_src * alpha_src
    color_f
    |> Nx.multiply(alpha_f)
    |> Nx.round()
    |> Nx.as_type(tensor.type)
  end

  defp ensure_3d(tensor) do
    case tensor.shape do
      {height, width} -> Nx.reshape(tensor, {height, width, 1})
      {_height, _width, _channels} -> tensor
    end
  end

  defp max_channel_value({:u, bits}), do: trunc(:math.pow(2, bits) - 1)
  defp max_channel_value({:s, bits}), do: trunc(:math.pow(2, bits - 1) - 1)
  defp max_channel_value({:f, _bits}), do: 1.0
end
