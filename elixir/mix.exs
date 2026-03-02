defmodule TurboToken.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :turbotoken,
      version: @version,
      elixir: "~> 1.14",
      compilers: [:elixir_make | Mix.compilers()],
      make_targets: ["all"],
      make_clean: ["clean"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "The fastest BPE tokenizer on every platform — drop-in tiktoken replacement",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :crypto]
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.8", runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/turbotoken/turbotoken"},
      files: ["lib", "c_src", "Makefile", "mix.exs", "README.md", "LICENSE"]
    ]
  end
end
