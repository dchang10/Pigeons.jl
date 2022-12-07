"""
pair_swapper: an informal interface, implementations take care of performing a swap between two parallel tempering chains.

A pair_swapper first extracts sufficient statistics needed to perform a swap (potentially to be transmitted over network).
    In the typical case, this will be log densities before and after proposed swap (or just the likelihood with linear 
    annealing paths), and a uniform [0, 1] variate.

Then based on two sets of sufficient statistics, deterministically decide if we should swap. 
"""
# swap_stat(pair_swapper, replica::Replica, partner_chain::Int) = @abstract
# swap_decision(pair_swapper, chain1::Int, stat1, chain2::Int, stat2)::Bool = @abstract
# record_swap_stats!(pair_swapper, recorder, chain1::Int, stat1, chain2::Int, stat2) = @abstract


"""
Default pair_swapper: assume pair_swapper conforms the log_potentials interface. 
"""
struct SwapStat 
    log_ratio::Float64 
    uniform::Float64
end
function swap_stat(log_potentials, replica::Replica, partner_chain::Int) 
    my_chain = replica.chain
    log_ratio = log_unnormalized_ratio(log_potentials, partner_chain, my_chain, replica.state)
    return SwapStat(log_ratio, rand(replica.rng))
end
function record_swap_stats!(pair_swapper, recorder, chain1::Int, stat1, chain2::Int, stat2)
    acceptance_pr = swap_acceptance_probability(stat1, stat2)
    index = min(chain1, chain2)
    fit_if_defined!(recorder, :swap_acceptance_pr, (index, acceptance_pr))
    # TODO accumulate stepping-stone statistics
end
function swap_decision(pair_swapper, chain1::Int, stat1, chain2::Int, stat2)
    acceptance_pr = swap_acceptance_probability(stat1, stat2)
    uniform = chain1 < chain2 ? stat1.uniform : stat2.uniform
    return uniform < acceptance_pr
end
swap_acceptance_probability(stat1::SwapStat, stat2::SwapStat) = min(1, exp(stat1.log_ratio + stat2.log_ratio))

"""
For testing/benchmarking purpose, a simple swap model where all swaps have equal acceptance probability. 

Could also be used to pre-warm-start swap connections during exploration phase by setting pr = 0. 
"""
struct TestSwapper 
    constant_swap_accept_pr::Float64
end
swap_stat(swapper::TestSwapper, replica::Replica, partner_chain::Int)::Float64 = rand(replica.rng)
function swap_decision(swapper::TestSwapper, chain1::Int, stat1::Float64, chain2::Int, stat2::Float64)::Bool 
    uniform = chain1 < chain2 ? stat1 : stat2
    return uniform < swapper.constant_swap_accept_pr
end
record_swap_stats!(swapper::TestSwapper, recorder, chain1::Int, stat1, chain2::Int, stat2) = nothing