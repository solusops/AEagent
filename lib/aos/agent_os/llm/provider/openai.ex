defmodule AOS.AgentOS.LLM.Provider.OpenAI do
  @moduledoc """
  API-backed provider for OpenAI-compatible chat completions.
  """

  alias AOS.AgentOS.Config
  alias AOS.AgentOS.LLM.Usage
  alias AOS.HTTPClient

  def call(prompt, history, opts) do
    model = Keyword.get(opts, :model) || Config.agent_model()
    tools = Keyword.get(opts, :tools)
    base_url = Config.agent_base_url()
    api_key = Config.agent_api_key()

    {url, body} = prepare_request(base_url, model, prompt, history, tools)
    headers = [{"Authorization", "Bearer #{api_key}"}, {"Content-Type", "application/json"}]

    case HTTPClient.post(url, body, headers, timeout: 60_000, recv_timeout: 60_000) do
      {:ok, %{status: 200, body: resp_body}} ->
        parse_raw_response(resp_body)

      {:ok, %{status: status}} when status in [429, 500, 502, 503, 504] ->
        {:error, {:retryable_http_error, status}}

      {:ok, %{status: status, body: body}} ->
        {:error, "API Error: #{status} #{body}"}

      {:error, reason} ->
        {:error, {:transport_error, reason}}
    end
  end

  def list_models do
    base_url = Config.agent_base_url()
    api_key = Config.agent_api_key()
    url = "#{String.replace(base_url, ~r|/v1beta$|, "")}/v1/models"
    headers = [{"Authorization", "Bearer #{api_key}"}]

    case HTTPClient.get(url, headers) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, Enum.map(data["data"] || [], & &1["id"])}
          {:error, reason} -> {:error, {:invalid_models_response, reason}}
        end

      _ ->
        {:error, :failed_to_list_models}
    end
  end

  defp prepare_request(base_url, model, prompt, history, tools) do
    messages =
      Enum.flat_map(history, fn
        {"user", content} ->
          [%{role: "user", content: scrub_utf8(content)}]

        {"assistant", %{tool_calls: calls}} ->
          [
            %{
              role: "assistant",
              tool_calls:
                Enum.map(calls, fn c ->
                  %{
                    id: c["id"],
                    type: "function",
                    function: %{name: c["name"], arguments: Jason.encode!(c["arguments"])}
                  }
                end)
            }
          ]

        {"assistant", content} ->
          [%{role: "assistant", content: scrub_utf8(content)}]

        {"tool", %{id: id, name: name, content: content}} ->
          text_content =
            case content do
              %{content: [%{text: t} | _]} -> scrub_utf8(t)
              _ -> scrub_utf8(inspect(content))
            end

          [%{role: "tool", tool_call_id: id, name: name, content: text_content}]

        {"system", content} ->
          [%{role: "system", content: scrub_utf8(content)}]
      end)

    messages =
      if prompt, do: messages ++ [%{role: "user", content: scrub_utf8(prompt)}], else: messages

    payload = %{
      model: String.replace(model, ~r|^models/|, ""),
      messages: messages,
      tools:
        if(tools,
          do:
            Enum.map(tools, fn t ->
              %{
                type: "function",
                function: %{
                  name: "#{t["server_id"]}__#{t["name"]}",
                  description: t["description"],
                  parameters: t["inputSchema"]
                }
              }
            end)
        )
    }

    {"#{String.replace(base_url, ~r|/v1beta$|, "")}/v1/chat/completions", Jason.encode!(payload)}
  end

  defp scrub_utf8(text) when is_binary(text) do
    text |> String.chunk(:valid) |> Enum.filter(&String.valid?/1) |> Enum.join("")
  end

  defp scrub_utf8(any), do: any

  defp parse_raw_response(body) do
    case Jason.decode(body) do
      {:ok, data} -> parse_decoded_response(data)
      {:error, reason} -> {:error, {:invalid_json_response, reason}}
    end
  end

  defp parse_decoded_response(data) do
    choice = get_in(data, ["choices", Access.at(0), "message"])
    usage = Usage.normalize_usage(data["usage"])
    model = data["model"]

    parse_choice(choice, usage, model)
  end

  defp parse_choice(%{"tool_calls" => tool_calls}, usage, model) do
    case parse_tool_calls(tool_calls) do
      {:ok, calls} -> {:ok, Usage.build_tool_call_response(calls, usage, model)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_choice(%{"content" => content}, usage, model) when is_binary(content),
    do: {:ok, Usage.build_text_response(content, usage, model)}

  defp parse_choice(_choice, _usage, _model), do: {:error, :empty_response}

  defp parse_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.reduce_while(tool_calls, {:ok, []}, fn tool_call, {:ok, acc} ->
      case parse_tool_call(tool_call) do
        {:ok, call} -> {:cont, {:ok, [call | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, calls} -> {:ok, Enum.reverse(calls)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_tool_calls(_tool_calls), do: {:error, :invalid_tool_calls}

  defp parse_tool_call(%{"id" => id, "function" => %{"name" => name} = function}) do
    case Jason.decode(function["arguments"] || "{}") do
      {:ok, arguments} ->
        {:ok, %{"id" => id, "name" => name, "arguments" => arguments}}

      {:error, reason} ->
        {:error, {:invalid_tool_arguments, name, reason}}
    end
  end

  defp parse_tool_call(_tool_call), do: {:error, :invalid_tool_call}
end
