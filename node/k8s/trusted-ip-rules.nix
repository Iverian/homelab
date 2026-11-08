# Mutually exclusive classes; each route retains its own counters.
builtins.concatMap
  (cidr: map
    (trusted: {
      clientSelectors = [ {
        headers = [ {
          name = "x-homelab-rate-tier";
          type = "Exact";
          value = "trusted";
          invert = !trusted;
        } ];
        sourceCIDR = { type = "Distinct"; value = cidr; };
      } ];
      limit = { requests = if trusted then 1200 else 100; unit = "Minute"; };
      shared = false;
    }) [ false true ])
  [ "0.0.0.0/0" "::/0" ]
