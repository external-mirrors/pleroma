defmodule Pleroma.Chaos do
  def kill_random_worker(pid) do
    with true <- Enum.random(0..100) >= 75 do
      Process.exit(pid, :kill)
    end
  end
end
