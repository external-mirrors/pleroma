# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Domains do
  def put_current_base(base) do
    Process.put(Pleroma.Web.Domains, base)
  end

  def get_current_base do
    Process.get(Pleroma.Web.Domains)
  end
end
