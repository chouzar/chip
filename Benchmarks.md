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

Generally speaking it seems to have lower numbers but we didn't get any big performance gains. 

Benchmark for `chip.find(registry, id)` but with an `ETS` implementation: 

```gleam
Name                        ips        average  deviation         median         99th %
a 10 chip.find         782.19 K        1.28 μs  ±1733.46%        1.17 μs        1.42 μs
b 100 chip.find        780.29 K        1.28 μs  ±1607.52%        1.17 μs        1.42 μs
c 1000 chip.find       781.99 K        1.28 μs  ±1689.63%        1.17 μs        1.54 μs
d 10000 chip.find      792.87 K        1.26 μs  ±1557.83%        1.17 μs        1.58 μs

Comparison: 
d 10000 chip.find      792.87 K
a 10 chip.find         782.19 K - 1.01x slower +0.0172 μs
c 1000 chip.find       781.99 K - 1.01x slower +0.0175 μs
b 100 chip.find        780.29 K - 1.02x slower +0.0203 μs
```

Again, this one seems to be a bit slower than the previous benchmark, it also doesn't seem to take the performance hit with a growing number of subjects.

The most drastic changes between implementations where in the memoru of the actor process itself, on `10_000` subjects:

* The process down selector implementation consumed about 24MB of memory.
* The dynamic selector implementation consumed about 7MB of memory.
* The `ETS` implementation consumed about 3MB of memory (`ETS` tables not accounted for).

Current memory benchmarks are rough so take the numbers above with a grain of salt.

## Fix dispatch bloat

### In memory sequential benchmarks

The current implementation for dispatch works by:

*  retrieving all subjects in a group (memory expensive)
*  executing the callback sequentially through all subjects (performance expensive)

Benchmark for `chip.dispatch(registry)`: 

```gleam
Name                            ips        average  deviation         median         99th %
a 10 chip.dispatch          80.57 K       12.41 μs    ±94.48%       10.92 μs       35.29 μs
b 100 chip.dispatch         11.10 K       90.06 μs   ±102.79%       76.42 μs      233.84 μs
c 1000 chip.dispatch         1.10 K      913.18 μs    ±59.98%      854.17 μs     1746.60 μs
d 10000 chip.dispatch      0.0899 K    11118.95 μs    ±17.24%    10723.71 μs    17190.42 μs

Comparison: 
a 10 chip.dispatch          80.57 K
b 100 chip.dispatch         11.10 K - 7.26x slower +77.65 μs
c 1000 chip.dispatch         1.10 K - 73.57x slower +900.77 μs
d 10000 chip.dispatch      0.0899 K - 895.85x slower +11106.53 μs
```

Benchmark for `chip.dispatch(registry, group)`: 

```gleam
Name                                  ips        average  deviation         median         99th %
a 10 chip.dispatch_group         161.77 K        6.18 μs   ±451.67%        4.96 μs       17.96 μs
b 100 chip.dispatch_group         32.44 K       30.83 μs    ±85.46%       27.63 μs       91.46 μs
c 1000 chip.dispatch_group         2.73 K      366.31 μs    ±38.42%      352.63 μs      720.08 μs
d 10000 chip.dispatch_group        0.27 K     3639.24 μs    ±24.68%     3331.63 μs     6315.83 μs

Comparison: 
a 10 chip.dispatch_group         161.77 K
b 100 chip.dispatch_group         32.44 K - 4.99x slower +24.65 μs
c 1000 chip.dispatch_group         2.73 K - 59.26x slower +360.13 μs
d 10000 chip.dispatch_group        0.27 K - 588.73x slower +3633.06 μs
```

The above is clearly inneficient, as the registry grows it will take much more time to fullfill tasks. One way to solve this issue is to do the dispatch in-process as to not bloat the client, then have a throttled dispatch as to not overload the actor itself. 

### In memory throttled benchmarks

Benchmark for `chip.dispatch(registry)` with the new dispatch mechanism: 

```gleam
Name                            ips        average  deviation         median         99th %
a 10 chip.dispatch           2.93 M      341.08 ns  ±1747.43%         292 ns         833 ns
b 100 chip.dispatch          2.83 M      353.51 ns  ±2352.31%         292 ns         833 ns
c 1000 chip.dispatch         2.55 M      392.60 ns  ±2823.81%         333 ns         791 ns
d 10000 chip.dispatch        2.32 M      431.21 ns  ±5178.39%         333 ns         958 ns

Comparison: 
a 10 chip.dispatch           2.93 M
b 100 chip.dispatch          2.83 M - 1.04x slower +12.43 ns
c 1000 chip.dispatch         2.55 M - 1.15x slower +51.52 ns
d 10000 chip.dispatch        2.32 M - 1.26x slower +90.12 ns
```

Benchmark for `chip.dispatch(registry, group)` with the new dispatch mechanism: 

```gleam
Name                                  ips        average  deviation         median         99th %
a 10 chip.dispatch_group           1.86 M      538.42 ns  ±7892.94%         333 ns        1333 ns
b 100 chip.dispatch_group          1.57 M      638.28 ns  ±8986.18%         292 ns        1250 ns
c 1000 chip.dispatch_group         1.09 M      916.82 ns ±12653.89%         292 ns        2291 ns
d 10000 chip.dispatch_group        0.99 M     1006.08 ns  ±3686.13%         292 ns        2958 ns

Comparison: 
a 10 chip.dispatch_group           1.86 M
b 100 chip.dispatch_group          1.57 M - 1.19x slower +99.86 ns
c 1000 chip.dispatch_group         1.09 M - 1.70x slower +378.40 ns
d 10000 chip.dispatch_group        0.99 M - 1.87x slower +467.66 ns
```

For both benchmarks above we went from several micro seconds into nano seconds. Granted this doesn't mean the dispatch was fulfilled faster only that the callers returned immediately because these are now a `send` operation, rather than a `call`. 

### ETS implementation benchmarks

Benchmark for `chip.dispatch(registry)` with an `ETS` implementation: 

```gleam
Name                            ips        average  deviation         median         99th %
a 10 chip.dispatch           3.01 M      332.44 ns  ±3759.74%         292 ns         625 ns
b 100 chip.dispatch          2.67 M      374.34 ns  ±5224.41%         333 ns         667 ns
d 10000 chip.dispatch        2.55 M      391.56 ns  ±4601.28%         333 ns         708 ns
c 1000 chip.dispatch         2.38 M      420.92 ns  ±4807.47%         375 ns         750 ns

Comparison: 
a 10 chip.dispatch           3.01 M
b 100 chip.dispatch          2.67 M - 1.13x slower +41.90 ns
d 10000 chip.dispatch        2.55 M - 1.18x slower +59.12 ns
c 1000 chip.dispatch         2.38 M - 1.27x slower +88.48 ns
```

Benchmark for `chip.dispatch_group(registry, group)` with an `ETS` implementation: 

```gleam
Name                                  ips        average  deviation         median         99th %
a 10 chip.dispatch_group           2.31 M      433.04 ns  ±3493.78%         334 ns         875 ns
b 100 chip.dispatch_group          1.69 M      592.41 ns  ±4017.50%         333 ns        1209 ns
c 1000 chip.dispatch_group         1.51 M      662.83 ns  ±4752.98%         292 ns        1375 ns
d 10000 chip.dispatch_group        1.23 M      809.97 ns  ±9557.57%         333 ns        1958 ns

Comparison: 
a 10 chip.dispatch_group           2.31 M
b 100 chip.dispatch_group          1.69 M - 1.37x slower +159.37 ns
c 1000 chip.dispatch_group         1.51 M - 1.53x slower +229.79 ns
d 10000 chip.dispatch_group        1.23 M - 1.87x slower +376.93 ns
```

Similar to previous case we go into the nano-seconds. Although I still not fully grok the time increase with a bigger registry.

### Make in memory throttled and ETS benchmarks return

For example, if we made this a `call` and waited for `chip.dispatch(registry)` to finish.

In memory throttled:

```gleam
Name                            ips        average  deviation         median         99th %
a 10 chip.dispatch          33.85 K      0.0295 ms   ±440.19%      0.0274 ms      0.0655 ms
b 100 chip.dispatch          3.51 K        0.28 ms    ±22.01%        0.27 ms        0.52 ms
c 1000 chip.dispatch         0.34 K        2.92 ms    ±15.16%        2.76 ms        4.52 ms
d 10000 chip.dispatch      0.0317 K       31.59 ms     ±8.30%       31.07 ms       42.42 ms
```

ETS:

```gleam
Name                            ips        average  deviation         median         99th %
a 10 chip.dispatch          33.78 K      0.0296 ms    ±86.19%      0.0285 ms      0.0535 ms
b 100 chip.dispatch          3.42 K        0.29 ms    ±23.80%        0.28 ms        0.46 ms
c 1000 chip.dispatch         0.32 K        3.10 ms    ±13.20%        2.97 ms        4.63 ms
d 10000 chip.dispatch      0.0303 K       33.02 ms    ±15.85%       30.94 ms       57.57 ms
```

It looks like the numbers got worse! This is probably due to the cap of 8 concurrent tasks going on at the same time. However I would rather have this dispatch be slow and then tweak it as I go along.


