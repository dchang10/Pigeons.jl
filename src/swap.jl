"""
Implementation of swap! (an informal interface method defined in replicas)
"""

"""
Single process implementation
"""
function swap!(pair_swapper, replicas::Vector{R}, swap_graph) where R
    @assert sorted(replicas)
    # perform the swaps
    for my_chain in eachindex(replicas)
        my_replica = replicas[my_chain]
        partner_chain = checked_partner_chain(swap_graph, my_chain)
        if partner_chain >= my_chain
            partner_replica = replicas[partner_chain]
            @assert partner_replica.chain == partner_chain
            my_swap_stat      = swap_stat(pair_swapper, my_replica, partner_chain)
            partner_swap_stat = partner_chain == my_chain ? 
                my_swap_stat :
                swap_stat(pair_swapper, partner_replica, my_chain)
            _swap!(pair_swapper, my_replica,      my_swap_stat,      partner_swap_stat, partner_chain)
            _swap!(pair_swapper, partner_replica, partner_swap_stat, my_swap_stat,      my_chain)
        end
    end
    # re-sort
    for my_chain in eachindex(replicas)
        my_replica = replicas[my_chain]
        if my_replica.chain != my_chain
            partner_chain = my_replica.chain
            partner_replica = replicas[partner_chain]
            @assert partner_replica.chain == my_chain
            replicas[my_chain]      = partner_replica
            replicas[partner_chain] = my_replica
        end
    end
end

function sorted(replicas) 
    for i in eachindex(replicas)
        if i != replicas[i].chain
            return false
        end
    end
    return true
end

"""
Entangled MPI implementation.

This implementation is designed to support distributed PT with the following guarantees
    - The running time is independent of the size of the state space 
      ('swapping annealing parameters rather than states')
    - The output is identical no matter how many MPI processes are used. In particular, 
      this means that we can check correctness by comparing to the serial, # process = 1 version.
    - Scalability to 1000s of processes communicating over MPI (see details below).
    - The same function can be used when a single process is used and MPI is not available.
    - Flexibility to extend PT to e.g. networks of targets and general paths.

For more information on input argument..
    - swapper, see below, example in test/swap_test.jl, and [TODO: default implementation at ____.jl]
    - replicas, see Replicas.jl
    - swap_graph, see swap_graphs.jl


Running time analysis. 

Let N denote the number of chains, P, the number of processes, and K = ceil(N/P),  
the maximum number of chains held by one process. 
Assuming the running time is dominated by communication latency and 
a constant time for the latency of each  
peer-to-peer communication, the theoretical running time is O(K). 
In practice, latency will grow as a function of P, but empirically,
this growth appears to be slow enough that for say P = N = few 1000s, 
swapping will not be the computational bottleneck.

Emphasis is on scaling laws rather than constants. For example, the current implementation 
allocates O(N) while in the case of a single 
process, it would be possible to have a no-allocation implementation. However again it is 
unlikely that this method would be the bottleneck in single-process mode.
"""
function swap!(pair_swapper, replicas::EntangledReplicas, swap_graph)
    # what chains (annealing parameters) are we swapping with?
    partner_chains = [checked_partner_chain(swap_graph, replicas.locals[i].chain) for i in eachindex(replicas.locals)]

    # translate these annealing parameters (chains) into replica global indices (so that we can find machines that hold them)
    partner_replica_global_indices = permuted_get(replicas.chain_to_replica_global_indices, partner_chains)

    # assemble sufficient statistics needed to perform a swap (for vanilla PT, log likelihood and a uniform variate)
    # ... for each of my replicas
    my_swap_stats = [swap_stat(pair_swapper, replicas.locals[i], partner_chains[i]) for i in eachindex(replicas.locals)]
    # ... and their partners via MPI
    partner_swap_stats = transmit(entangler(replicas), my_swap_stats, partner_replica_global_indices)

    # each call of _swap! performs "one half" of a swap, changing one replicas' chain field in-place
    for i in eachindex(replicas.locals)
        _swap!(pair_swapper, replicas.locals[i], my_swap_stats[i], partner_swap_stats[i], partner_chains[i])
    end

    # update the distributed array linking chains to replicas
    my_replica_global_indices = my_global_indices(replicas.chain_to_replica_global_indices.entangler.load)
    permuted_set!(replicas.chain_to_replica_global_indices, chain.(replicas.locals), my_replica_global_indices)
end

# Private low-level functions shared by all implementations:

function _swap!(pair_swapper, r::Replica, my_swap_stat, partner_swap_stat, partner_chain::Int)
    my_chain = r.chain
    if my_chain == partner_chain return nothing end

    do_swap          =  swap_decision(pair_swapper, my_chain, my_swap_stat, partner_chain, partner_swap_stat)
    @assert do_swap  == swap_decision(pair_swapper, partner_chain, partner_swap_stat, my_chain, my_swap_stat)

    if my_chain < partner_chain
        record_swap_stats!(pair_swapper, r.recorder, my_chain, my_swap_stat, partner_chain, partner_swap_stat)
    end

    if do_swap
        r.chain = partner_chain # NB: other "half" of the swap performed by partner
    end
end

function checked_partner_chain(swap_graph, my_chain::Int)::Int 
    result            = partner_chain(swap_graph, my_chain)
    @assert my_chain == partner_chain(swap_graph, result)
    return result
end