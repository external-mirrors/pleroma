# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.ArticleNotePageValidator do
  use Ecto.Schema

  alias Pleroma.EctoType.ActivityPub.ObjectValidators
  alias Pleroma.Web.ActivityPub.ObjectValidators.CommonFixes
  alias Pleroma.Web.ActivityPub.ObjectValidators.CommonValidations
  alias Pleroma.Web.ActivityPub.Transmogrifier

  import Ecto.Changeset

  @primary_key false
  @derive Jason.Encoder

  embedded_schema do
    quote do
      unquote do
        import Elixir.Pleroma.Web.ActivityPub.ObjectValidators.CommonFields
        message_fields()
        object_fields()
        status_object_fields()
      end
    end

    field(:replies, {:array, ObjectValidators.ObjectID}, default: [])
    field(:replies_collection, ObjectValidators.ObjectID)
  end

  def cast_and_apply(data, opts \\ []) do
    data
    |> cast_data(opts)
    |> apply_action(:insert)
  end

  def cast_and_validate(data, opts \\ []) do
    data
    |> cast_data(opts)
    |> validate_data()
  end

  def cast_data(data, opts \\ []) do
    %__MODULE__{}
    |> changeset(data, opts)
  end

  defp fix_url(%{"url" => url} = data) when is_bitstring(url), do: data
  defp fix_url(%{"url" => url} = data) when is_map(url), do: Map.put(data, "url", url["href"])
  defp fix_url(data), do: data

  defp fix_tag(%{"tag" => tag} = data) when is_list(tag) do
    Map.put(data, "tag", Enum.filter(tag, &is_map/1))
  end

  defp fix_tag(%{"tag" => tag} = data) when is_map(tag), do: Map.put(data, "tag", [tag])
  defp fix_tag(data), do: Map.drop(data, ["tag"])

  defp fix_replies_collection(data, opts) do
    collection_id = replies_collection_candidate(data, opts)
    data = Map.delete(data, "replies_collection")

    with collection_id when is_binary(collection_id) <- collection_id,
         {:ok, collection_id} <- ObjectValidators.ObjectID.cast(collection_id),
         true <- same_origin?(collection_id, data["id"]) do
      Map.put(data, "replies_collection", collection_id)
    else
      _ -> data
    end
  end

  defp replies_collection_candidate(data, opts) do
    case replies_collection_id(data["replies"]) do
      nil -> internal_replies_collection_id(data, opts)
      collection_id -> collection_id
    end
  end

  defp internal_replies_collection_id(
         %{"replies" => replies, "replies_collection" => collection_id},
         opts
       )
       when is_list(replies) and is_binary(collection_id) do
    if Keyword.get(opts, :preserve_internal_replies_collection) do
      collection_id
    end
  end

  defp internal_replies_collection_id(_, _), do: nil

  defp replies_collection_id(replies) when is_binary(replies), do: replies

  defp replies_collection_id(%{"id" => id}) when is_binary(id), do: id

  defp replies_collection_id(%{"first" => %{"partOf" => id}}) when is_binary(id), do: id

  defp replies_collection_id(_), do: nil

  defp same_origin?(left, right) when is_binary(left) and is_binary(right) do
    left = URI.parse(left)
    right = URI.parse(right)

    is_binary(left.scheme) and is_binary(left.host) and is_binary(right.scheme) and
      is_binary(right.host) and left.scheme == right.scheme and
      String.downcase(left.host) == String.downcase(right.host) and
      uri_port(left) == uri_port(right)
  end

  defp same_origin?(_, _), do: false

  defp uri_port(%URI{port: nil, scheme: scheme}), do: URI.default_port(scheme)
  defp uri_port(%URI{port: port}), do: port

  # legacy internal *oma format
  defp fix_replies(%{"replies" => replies} = data) when is_list(replies), do: data

  defp fix_replies(%{"replies" => %{"first" => %{"items" => replies}}} = data)
       when is_list(replies),
       do: Map.put(data, "replies", replies)

  defp fix_replies(%{"replies" => %{"first" => %{"orderedItems" => replies}}} = data)
       when is_list(replies),
       do: Map.put(data, "replies", replies)

  defp fix_replies(%{"replies" => %{"items" => replies}} = data) when is_list(replies),
    do: Map.put(data, "replies", replies)

  defp fix_replies(%{"replies" => %{"orderedItems" => replies}} = data) when is_list(replies),
    do: Map.put(data, "replies", replies)

  defp fix_replies(data), do: Map.delete(data, "replies")

  def fix_attachments(%{"attachment" => attachment} = data) when is_map(attachment),
    do: Map.put(data, "attachment", [attachment])

  def fix_attachments(data), do: data

  defp fix(data, opts) do
    data
    |> CommonFixes.fix_actor()
    |> fix_replies_collection(opts)
    |> CommonFixes.fix_object_defaults()
    |> fix_url()
    |> fix_tag()
    |> fix_replies()
    |> fix_attachments()
    |> CommonFixes.fix_quote_url()
    |> CommonFixes.fix_likes()
    |> Transmogrifier.fix_emoji()
    |> Transmogrifier.fix_content_map()
    |> CommonFixes.maybe_add_language()
    |> CommonFixes.maybe_add_content_map()
  end

  def changeset(struct, data, opts \\ []) do
    data = fix(data, opts)

    struct
    |> cast(data, __schema__(:fields) -- [:attachment, :tag])
    |> cast_embed(:attachment)
    |> cast_embed(:tag)
  end

  defp validate_data(data_cng) do
    data_cng
    |> validate_inclusion(:type, ["Article", "Note", "Page"])
    |> validate_required([:id, :actor, :attributedTo, :type, :context])
    |> CommonValidations.validate_any_presence([:cc, :to])
    |> CommonValidations.validate_fields_match([:actor, :attributedTo])
    |> CommonValidations.validate_actor_presence()
    |> CommonValidations.validate_host_match()
  end
end
