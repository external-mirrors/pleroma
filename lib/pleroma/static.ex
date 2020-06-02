# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Static do
  require Pleroma.Constants

  def static_only_files do
    static_folder =
      Pleroma.Config.get([:instance, :static_dir], "instance/static/")

    add =
      if Pleroma.Static.use_instance_static_files() do
        case File.ls(static_folder) do
          {:error, _} -> []
          {:ok, files} -> files
        end
      else
        []
      end

    Enum.uniq(Pleroma.Constants.static_only_files() ++ add)
  end

  def use_instance_static_files do
    case System.get_env("USE_INSTANCE_STATIC_FILES") do
      nil ->
        Pleroma.Config.get([:instance, :use_instance_static_files], true)
      value -> value === "y" || value === "1" || value === "true"
    end
  end
end
