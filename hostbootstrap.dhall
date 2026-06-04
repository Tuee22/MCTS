let container =
      H.Model.Container
        H.Container::{
        , dockerfile = "docker/Dockerfile"
        , service = False
        }

in  H.configWithDevelopment
      True
      { project = "mcts"
      , substrates =
        [ H.entry H.Substrate.AppleSilicon container
        , H.entry H.Substrate.LinuxCpu container
        , H.entry H.Substrate.LinuxGpu container
        ]
      }
