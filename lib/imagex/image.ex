defmodule Imagex.Image do
  @moduledoc """
  Represents an image, including its tensor and metadata
  """

  @type tensor :: Nx.Tensor.t()
  @type metadata :: map()

  @type t :: %Imagex.Image{tensor: tensor, metadata: metadata}

  @enforce_keys [:tensor]
  defstruct [:tensor, :metadata]
end
