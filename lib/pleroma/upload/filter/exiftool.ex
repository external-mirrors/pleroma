# Pleroma: A lightweight social networking server
# Copyright © Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Upload.Filter.Exiftool do
  @moduledoc """
  Deprecated wrapper around `Pleroma.Upload.Filter.Exif.StripLocation`.
  """

  @behaviour Pleroma.Upload.Filter

  @deprecated "Use Pleroma.Upload.Filter.Exif.StripLocation"
  defdelegate filter(upload), to: Pleroma.Upload.Filter.Exif.StripLocation
end
