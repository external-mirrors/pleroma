# Pleroma: A lightweight social networking server
# Copyright © 2017-2023 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.MediaView do
  use Pleroma.Web, :view

  alias Pleroma.Web.MastodonAPI.StatusView

  def render("index.json", %{media: media, for: viewer}) do
    Enum.map(media, fn attachment ->
      StatusView.render("attachment.json", %{attachment: attachment, for: viewer})
    end)
  end
end
