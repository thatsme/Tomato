exclude =
  if System.find_executable("nix-instantiate"), do: [], else: [:nix_cli]

ExUnit.start(exclude: exclude)
