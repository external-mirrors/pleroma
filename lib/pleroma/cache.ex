defmodule Pleroma.Cache do
  alias Pleroma.Cache.Config

  use Nebulex.Cache,
    otp_app: :pleroma,
    adapter: Config.adapter(Nebulex.Adapters.Local)
end
