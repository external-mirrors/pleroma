defmodule Pleroma.Chaos do
  def kill_random_worker(pid) do
    with true <- :sys.get_state(pid).pool in [:media, :rich_media],
         true <- Enum.random(0..10) >= 5 do
      Process.exit(pid, :kill)
    end
  end
end
