# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

exclude_tags = [
  {:federated, true},
  {:skip_on_mac, :os.type() == {:unix, :darwin}},
  {:skip_exiftool, not Pleroma.Utils.command_available?("exiftool")}
]

ExUnit.start(exclude: for({tag, use_tag} <- exclude_tags, use_tag, do: tag))

Ecto.Adapters.SQL.Sandbox.mode(Pleroma.Repo, :manual)

Mox.defmock(Pleroma.ReverseProxy.ClientMock, for: Pleroma.ReverseProxy.Client)
Mox.defmock(Pleroma.GunMock, for: Pleroma.Gun)

{:ok, _} = Application.ensure_all_started(:ex_machina)

ExUnit.after_suite(fn _results ->
  uploads = Pleroma.Config.get([Pleroma.Uploaders.Local, :uploads], "test/uploads")
  File.rm_rf!(uploads)
end)
