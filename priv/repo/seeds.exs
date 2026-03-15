# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     ExCortex.Repo.insert!(%ExCortex.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Seed pre-baked axioms from priv/dictionaries/*.csv
descriptions = %{
  "sports_teams" => "Sports teams across NFL, NBA, MLB, NHL, and MLS with abbreviations and divisions.",
  "stock_tickers" => "S&P 500 company names, ticker symbols, and sectors.",
  "wcag_criteria" => "WCAG 2.1 success criteria with level (A/AA/AAA) and descriptions.",
  "regulatory_frameworks" => "Major regulatory frameworks and compliance standards by jurisdiction and domain.",
  "currency_codes" => "ISO 4217 currency codes with names, symbols, and example countries."
}

# Load local settings overrides if present (gitignored, not checked in)
local_seeds = Path.join(__DIR__, "seeds.local.exs")
if File.exists?(local_seeds), do: Code.eval_file(local_seeds)

for path <- Path.wildcard("priv/dictionaries/*.csv") do
  name = Path.basename(path, ".csv")

  if !ExCortex.Lexicon.get_axiom_by_name(name) do
    content = File.read!(path)

    {:ok, _} =
      ExCortex.Lexicon.create_axiom(%{
        name: name,
        content: content,
        content_type: "csv",
        description: Map.get(descriptions, name, "Pre-baked reference dataset.")
      })

    IO.puts("Seeded axiom: #{name}")
  end
end
