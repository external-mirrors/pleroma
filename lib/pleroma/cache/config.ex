defmodule Pleroma.Cache.Config do
  def adapter(wanted) do
    # Disable Nebulex cache in test env
    if Pleroma.Config.get(:env) == :test do
      Nebulex.Adapters.Nil
    else
      wanted
    end
  end
end
