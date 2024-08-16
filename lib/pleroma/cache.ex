# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Cache do
  use Nebulex.Cache,
    otp_app: :pleroma,
    adapter: Nebulex.Adapters.Local
end
