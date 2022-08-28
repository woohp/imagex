defmodule Mix.Tasks.Compile.Imagex do
  def run(_) do
    {result, _error_code} = System.cmd("make", ["priv/imagex.so"], stderr_to_stdout: true)
    IO.binwrite(result)
    :ok
  end
end

defmodule Imagex.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :imagex,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      compilers: [:imagex, :elixir, :app],
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
      {:nx, "~> 0.3.0"}
    ]
  end
end
