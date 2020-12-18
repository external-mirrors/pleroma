# MRF policies descriptions

If MRF policy depends on config, it can be added into MRF tab to adminFE by adding `config_description/0` method, which returns map with special structure. See existing MRF's like mrf_simple for examples.

Example:

```elixir
%{
      key: :mrf_activity_expiration,
      related_policy: "Pleroma.Web.ActivityPub.MRF.ActivityExpirationPolicy",
      label: "MRF Activity Expiration Policy",
      description: "Adds automatic expiration to all local activities",
      children: [
        %{
          key: :days,
          type: :integer,
          description: "Default global expiration time for all local activities (in days)",
          suggestions: [90, 365]
        }
      ]
    }
```
