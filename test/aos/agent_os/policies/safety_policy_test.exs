defmodule AOS.AgentOS.Policies.SafetyPolicyTest do
  use ExUnit.Case, async: true

  alias AOS.AgentOS.Config
  alias AOS.AgentOS.Policies.SafetyPolicy

  test "blocks pii in result" do
    assert {:error, :pii_detected} =
             SafetyPolicy.check(
               %{task: "summarize", result: "email me at test@example.com"},
               :worker
             )
  end

  test "blocks dangerous destructive intent in task" do
    assert {:error, :dangerous_intent} =
             SafetyPolicy.check(%{task: "please run rm -rf / on the server"}, :worker)
  end

  test "blocks sibling write paths that share the workspace prefix" do
    workspace = Config.workspace_root()

    assert {:error, :unsafe_write_path} =
             SafetyPolicy.check(
               %{task: "write", last_write_path: workspace <> "_sibling/out.txt"},
               :worker
             )
  end
end
