defmodule ProtocolDep.MixProject do
  use Mix.Project

  def project do
    [
      app: :protocol_dep,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: []
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end
end
