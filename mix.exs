defmodule Imagex.MixProject do
  use Mix.Project

  @version "0.2.1"

  def project do
    [
      app: :imagex,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_env: fn -> %{"EXPP_INCLUDE_DIR" => Expp.include_dir()} end,
      make_targets: ["priv/imagex.so"],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
      {:nx, "~> 0.10"},
      {:expp, github: "woohp/expp", runtime: false},
      {:elixir_make, "~> 0.6", runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
