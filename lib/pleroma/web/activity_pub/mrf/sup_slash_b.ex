defmodule Site.SupSlashB do
	require Logger
    	@behaviour Pleroma.Web.ActivityPub.MRF

        	@impl true
            	def filter(
                    		%{
                                			"type" => "Create",
                                            			"actor" => actor,
                                                        			"object" => %{
                                                                        				"type" => "Note",
                                                                                        				"summary" => "/b/",
                                                                    } = object
                            } = message
                ) do
                                actor_info = URI.parse(actor)
                                                if(actor_info.host == "freespeechextremist.com") do
                                                                        #Logger.warn("sup /b/ #{inspect(object)}")
                                                                         
                                                                         			object =
                                                                                     				object
                                                                                                     				|> Map.put("actor", "https://freespeechextremist.com/users/slashb")
                                                                                                                     			message =
                                                                                                                                 				message
                                                                                                                                                 				|> Map.put("actor", "https://freespeechextremist.com/users/slashb")
                                                                                                                                                                 				|> Map.put("object", object)
                                                                                                                                                                                 			{:ok, message}
                                                                                                                                                                                                             else
                                                                                                                                                                                                                                     {:ok, message}
                                                                                                                                                                                                                                                     end
                                                                                                                                                                                                                                                     	end

                                                                                                                                                                                                                                                         	@impl true
                                                                                                                                                                                                                                                             	def filter(message), do: {:ok, message}
                                                                                                                                                                                                                                                                   @impl true
                                                                                                                                                                                                                                                                     def describe, do: {:ok, %{}}
                                                                                                                                                                                                                                                                     end
                                                                    }
                            }
                )