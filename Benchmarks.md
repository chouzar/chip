# Benchmarks

A log of benchmarks to better understand performance gains due to tweaks in the codebase.

## Fix selector bloat

The current implementation works all within memory, part of that is that each new subject added to the registry is added to the actor's selector (a gleam `Map`) in order to wait for possible `DOWN` messages in case the monitored process goes down.

This makes it so that each subsequent message in the actor needs to be searched for to validate that its a valid message. These are the current benchmarks.

Benchmark for `chip.find(registry, id)`: 

```gleam
Name                        ips        average  deviation         median         99th %
a 10 chip.find         672.30 K        1.49 μs   ±736.28%        1.38 μs        1.75 μs
b 100 chip.find        775.05 K        1.29 μs   ±770.60%        1.21 μs        2.38 μs
c 1000 chip.find       712.36 K        1.40 μs   ±733.53%        1.29 μs        1.71 μs
d 10000 chip.find      666.37 K        1.50 μs   ±734.12%        1.38 μs           2 μs

Comparison: 
b 100 chip.find        775.05 K
c 1000 chip.find       712.36 K - 1.09x slower +0.114 μs
a 10 chip.find         672.30 K - 1.15x slower +0.197 μs
d 10000 chip.find      666.37 K - 1.16x slower +0.21 μs
```

Code was modified as to allow for a "dynamic selector", with this we lose the built in type safety from OTP but also, we avoid making the selector larger with each new monitor.

Benchmark for `chip.find(registry, id)` but with new dynamic selector: 

```gleam
Name                        ips        average  deviation         median         99th %
b 100 chip.find        829.61 K        1.21 μs  ±2139.62%        1.13 μs        1.46 μs
a 10 chip.find         826.32 K        1.21 μs  ±1991.38%        1.13 μs        1.58 μs
c 1000 chip.find       823.33 K        1.21 μs  ±2130.62%        1.13 μs        1.42 μs
d 10000 chip.find      780.58 K        1.28 μs  ±1235.40%        1.17 μs        1.79 μs

Comparison: 
b 100 chip.find        829.61 K
a 10 chip.find         826.32 K - 1.00x slower +0.00480 μs
c 1000 chip.find       823.33 K - 1.01x slower +0.00919 μs
d 10000 chip.find      780.58 K - 1.06x slower +0.0757 μs
```

Generally speaking it seems to have lower numbers but we didn't got any big performance gains.
