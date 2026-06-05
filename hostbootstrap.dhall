let container =
      H.Model.Container
        ( H.Container::{
        , dockerfile = "docker/Dockerfile"
        , service = False
        , mounts =
          [ H.Mount::{ host = ".mcts-cache", container = "/workspace/MCTS/.mcts-cache" }
          ]
        }
        )

in  H.configWithDevelopment
      True
      { project = "mcts"
      , targets =
        [ H.target H.Accel.Cpu container
        ]
      }
