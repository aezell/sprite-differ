defmodule SpriteDiff.CLI do
  @moduledoc """
  Command-line interface for sprite-diff.
  """

  alias SpriteDiff.CLI.{Remote, Agent, Local}

  def main(args) do
    args
    |> parse_args()
    |> run()
  end

  defp parse_args(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        switches: [
          help: :boolean,
          json: :boolean,
          summary: :boolean,
          output: :string,
          file: :string,
          path: :string
        ],
        aliases: [h: :help, j: :json, s: :summary, o: :output, f: :file, p: :path]
      )

    {opts, args}
  end

  defp run({_opts, ["help" | _]}), do: print_help()

  defp run({opts, []}) do
    if opts[:help] do
      print_help()
    else
      print_help()
      System.halt(1)
    end
  end

  # Remote commands
  defp run({opts, ["checkpoints" | _] = args}), do: Remote.run(opts, args)
  defp run({opts, ["manifest" | _] = args}), do: Remote.run(opts, args)
  defp run({opts, ["diff" | _] = args}), do: Remote.run(opts, args)
  defp run({opts, ["file" | _] = args}), do: Remote.run(opts, args)

  # Agent commands
  defp run({opts, ["agent" | _] = args}), do: Agent.run(opts, args)

  # Local commands
  defp run({opts, ["local" | _] = args}), do: Local.run(opts, args)

  defp run({_opts, _args}) do
    print_help()
    System.halt(1)
  end

  defp print_help do
    IO.puts("""
    sprite-differ - Compare Sprites checkpoints

    USAGE:
      sprite-differ <command> [options]

    LOCAL COMMANDS (no API token needed):
      local manifest [checkpoint-id]               Create manifest of current filesystem
      local list                                   List local manifests
      local diff <manifest-a> <manifest-b>         Compare two manifest files

    REMOTE COMMANDS (requires SPRITES_TOKEN):
      checkpoints <sprite>                         List all checkpoints
      manifest <sprite> <checkpoint>               Generate manifest for checkpoint
      diff <sprite> <checkpoint-a> <checkpoint-b>  Compare two checkpoints
      file <sprite> <cp-a> <cp-b> <path>           Show file content diff

      agent install <sprite>                       Install manifest agent
      agent status <sprite>                        Check agent status
      agent uninstall <sprite>                     Remove manifest agent
      agent trigger <sprite>                       Manually create manifest

    OPTIONS:
      -h, --help      Show this help
      -j, --json      Output as JSON
      -s, --summary   Show only summary (for diff)
      -o, --output    Write output to file
      -p, --path      Base path to scan (default: /home)

    ENVIRONMENT:
      SPRITES_TOKEN   API token for remote commands
      SPRITES_API_URL API base URL (default: https://api.sprites.dev)

    EXAMPLES:
      # Local usage (on a sprite):
      sprite-differ local manifest before-changes
      sprite-differ local manifest after-changes
      sprite-differ local diff /.sprite-diff/manifests/before-changes.json \\
                               /.sprite-diff/manifests/after-changes.json

      # Remote usage (with API):
      sprite-differ checkpoints my-app
      sprite-differ diff my-app checkpoint-1 checkpoint-2
    """)
  end
end
