"""
A [`Base.@kwdef`](https://github.com/JuliaLang/julia/blob/79ceb8dbeab1b5a47c6bd664214616c19607ffab/base/util.jl#L514) struct 
used to create Parallel Tempering algorithms. 

Fields (see source file for default values):
$FIELDS
"""
@kwdef mutable struct Inputs{I}
    """ The target distribution. """
    target::I

    """ The master random seed. """
    seed::Int = 1

    """ The number of rounds to run. """
    n_rounds::Int = 10

    """ The number of chains to use. """
    n_chains::Int = 10

    """ The number of chains to use for the variational reference leg. """
    n_chains_variational::Int = 0
    
    """ 
    Whether a checkpoint should be written to disk 
    at the end of each round. 
    """
    checkpoint::Bool = false

    """
    An Vector with elements of type 
    [`recorder_builder`](@ref). 
    """
    recorder_builders::Vector = Function[]

    """
    The round index where [`run_checks()`](@ref) will 
    be performed. Set to 0 to skip these checks. 
    """
    checked_round::Int = 0

    """
    If multithreaded explorers should be allowed. 
    False by default since it incurs an overhead. 
    """
    multithreaded::Bool = false
end


function use_variational_reference(inputs::Inputs)
    if (inputs.n_chains_variational > 0)
        inputs.n_chains == 0 ? true : error("Two reference distributions have not yet been implemented.")
    else 
        return false
    end
end