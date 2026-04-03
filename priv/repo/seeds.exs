# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Falcon.Repo.insert!(%Falcon.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Falcon.Providers.Provider
alias Falcon.Repo

# M3 Mac (Tailscale) running qwen3-coder-next via Ollama
# Update the base_url to match your Tailscale IP/hostname
%Provider{}
|> Provider.changeset(%{
  name: "M3 Ollama",
  type: "ollama",
  base_url: "http://m3m:11434"
})
|> Repo.insert!(on_conflict: :nothing, conflict_target: :name)
