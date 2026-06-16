{ ... }:

{
  services.ironworks.hydraController = {
    enable = true;
    hostName = "hydra.example.org";
    useACME = false;
  };

  system.stateVersion = "25.11";
}
