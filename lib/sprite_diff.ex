defmodule SpriteDiff do
  @moduledoc """
  SpriteDiff - Compare Sprites checkpoints to see what changed.

  This library provides tools to:
  - List and inspect checkpoints
  - Generate filesystem manifests
  - Compare manifests to produce diffs
  - Install an agent for automatic manifest creation

  ## Usage

  ### CLI

      sprite-diff checkpoints my-sprite
      sprite-diff diff my-sprite checkpoint-a checkpoint-b
      sprite-diff agent install my-sprite

  ### Programmatic

      # List checkpoints
      {:ok, checkpoints} = SpriteDiff.list_checkpoints("my-sprite")

      # Compare checkpoints
      {:ok, diff} = SpriteDiff.compare("my-sprite", "cp-1", "cp-2")

      # Generate manifest
      {:ok, manifest} = SpriteDiff.manifest("my-sprite", "cp-1")
  """

  alias SpriteDiff.{API, Manifest, Diff}

  @doc """
  List all checkpoints for a sprite.
  """
  def list_checkpoints(sprite_name) do
    API.list_checkpoints(sprite_name)
  end

  @doc """
  Generate a manifest for a checkpoint.
  """
  def manifest(sprite_name, checkpoint_id, opts \\ []) do
    Manifest.generate(sprite_name, checkpoint_id, opts)
  end

  @doc """
  Compare two checkpoints and return a diff.
  """
  def compare(sprite_name, checkpoint_a, checkpoint_b) do
    Diff.compare(sprite_name, checkpoint_a, checkpoint_b)
  end

  @doc """
  Get the content diff for a specific file.
  """
  def file_diff(sprite_name, checkpoint_a, checkpoint_b, file_path) do
    Diff.file_diff(sprite_name, checkpoint_a, checkpoint_b, file_path)
  end

  @doc """
  Install the manifest agent on a sprite.
  """
  def install_agent(sprite_name) do
    SpriteDiff.Agent.install(sprite_name)
  end

  @doc """
  Check agent status on a sprite.
  """
  def agent_status(sprite_name) do
    SpriteDiff.Agent.status(sprite_name)
  end
end
