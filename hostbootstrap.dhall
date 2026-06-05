let container =
      H.Model.Container
        H.Container::{
        , dockerfile = "docker/Dockerfile"
        , mounts =
          [ H.Mount::{ host = ".mcts-cache", container = "/workspace/MCTS/.mcts-cache" }
          ]
        }

in  H.config
      { project = "mcts"
      , substrates =
        [ H.entry H.Substrate.AppleSilicon (H.noCluster container)
        , H.entry H.Substrate.LinuxCpu (H.noCluster container)
        , H.entry H.Substrate.LinuxGpu (H.noCluster container)
        ]
      }
