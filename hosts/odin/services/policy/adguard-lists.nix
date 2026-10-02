# AdGuardHome data for hosts/odin/services/policy.nix: the LAN rewrites and
# the curated upstream filter lists. Data, not policy — the lists are URLs
# with an on/off flag, and keeping them out of the module body is what makes
# the module readable.
let
  # Positional constructor for adguardhome.filterLists below: nixfmt keeps a
  # three-name `inherit` on one line, so each record costs one line.
  adguardFilter = name: url: enabled: { inherit name url enabled; };
in
{
  rewrites = [
    {
      domain = "odin";
      answer = "10.0.2.140";
    }
    {
      domain = "odin.local";
      answer = "10.0.2.140";
    }
  ];
  filterLists = [
    # Core/general
    (adguardFilter "AdGuard DNS filter"
      "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"
      true
    )
    (adguardFilter "OISD full" "https://big.oisd.nl/" true)
    (adguardFilter "AdAway" "https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt"
      false
    )

    # Well-known hostlists (mostly covered by OISD, kept optional)
    (adguardFilter "Peter Lowe's Blocklist"
      "https://adguardteam.github.io/HostlistsRegistry/assets/filter_3.txt"
      false
    )
    (adguardFilter "Dan Pollock's Hosts"
      "https://adguardteam.github.io/HostlistsRegistry/assets/filter_4.txt"
      false
    )
    (adguardFilter "Steven Black's List"
      "https://adguardteam.github.io/HostlistsRegistry/assets/filter_33.txt"
      false
    )

    # Security-focused
    (adguardFilter "Dandelion Sprout Anti‑Malware"
      "https://adguardteam.github.io/HostlistsRegistry/assets/filter_12.txt"
      true
    )
    (adguardFilter "Phishing Army"
      "https://adguardteam.github.io/HostlistsRegistry/assets/filter_18.txt"
      true
    )
    (adguardFilter "URLHaus Malicious URL"
      "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt"
      true
    )
    (adguardFilter "Scam Blocklist (DurableNapkin)"
      "https://adguardteam.github.io/HostlistsRegistry/assets/filter_10.txt"
      true
    )

    # Niche/optional
    (adguardFilter "NoCoin (Cryptomining)"
      "https://adguardteam.github.io/HostlistsRegistry/assets/filter_8.txt"
      false
    )
    (adguardFilter "Smart‑TV Blocklist"
      "https://adguardteam.github.io/HostlistsRegistry/assets/filter_7.txt"
      false
    )
    (adguardFilter "Game Console Adblock"
      "https://adguardteam.github.io/HostlistsRegistry/assets/filter_6.txt"
      false
    )
    (adguardFilter "1Hosts Lite" "https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt"
      false
    )
    (adguardFilter "1Hosts Xtra" "https://adguardteam.github.io/HostlistsRegistry/assets/filter_70.txt"
      false
    )

    # Regional (RU) — Adblock syntax lists; optional at DNS level
    (adguardFilter "AdGuard Russian filter" "https://filters.adtidy.org/extension/ublock/filters/2.txt"
      true
    )
    (adguardFilter "RU AdList + EasyList"
      "https://easylist-downloads.adblockplus.org/ruadlist+easylist.txt"
      true
    )
  ];
}
