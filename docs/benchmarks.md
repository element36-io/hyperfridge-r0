|     Cycles |   Duration |        RAM |       Seal |      Speed |
|     ---- |   ---- |        ---- |       ---- |      ---- |
|        64k |      8.14s |    472.4MB |    215.3kB |     8.1khz |
|       128k |     20.95s |    944.8MB |    238.3kB |     6.3khz |
|       256k |     46.62s |     1.89GB |      250kB |     5.6khz |
|       512k |     1:34.3 |     3.78GB |    262.2kB |     5.6khz |
|      1024k |     3:10.3 |     7.56GB |    275.5kB |     5.5khz |
|      2048k |     6:21.2 |     7.56GB |      551kB |     5.5khz |
|      4096k |    12:41.5 |     7.56GB |      1.1MB |     5.5khz |





cargo run --release --example loop

cargo run --release -F cuda --example loop


cargo bench --bench fib


cargo bench -F --bench fib


+