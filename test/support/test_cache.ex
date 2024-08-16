defmodule Pleroma.TestCache do
  use Nebulex.Cache,
    otp_app: :pleroma,
    adapter: Nebulex.Adapters.Nil
end
