## TYPES AND CONSTRUCTOR


mutable struct DeterministicTunedModel{T,M<:Deterministic} <: MLJBase.Deterministic
    model::M
    tuning::T  # tuning strategy
    resampling # resampling strategy
    measure
    weights::Union{Nothing,Vector{<:Real}}
    operation
    range
    selection_heuristic
    train_best::Bool
    repeats::Int
    n::Union{Int,Nothing}
    acceleration::AbstractResource
    acceleration_resampling::AbstractResource
    check_measure::Bool
    cache::Bool
end

mutable struct ProbabilisticTunedModel{T,M<:Probabilistic} <: MLJBase.Probabilistic
    model::M
    tuning::T  # tuning strategy
    resampling # resampling strategy
    measure
    weights::Union{Nothing,AbstractVector{<:Real}}
    operation
    range
    selection_heuristic
    train_best::Bool
    repeats::Int
    n::Union{Int,Nothing}
    acceleration::AbstractResource
    acceleration_resampling::AbstractResource
    check_measure::Bool
    cache::Bool
end

const EitherTunedModel{T,M} =
    Union{DeterministicTunedModel{T,M},ProbabilisticTunedModel{T,M}}

#todo update:
"""
    tuned_model = TunedModel(; model=nothing,
                             tuning=Grid(),
                             resampling=Holdout(),
                             measure=nothing,
                             weights=nothing,
                             repeats=1,
                             operation=predict,
                             range=nothing,
                             selection_heuristic=NaiveSelection(),
                             n=default_n(tuning, range),
                             train_best=true,
                             acceleration=default_resource(),
                             acceleration_resampling=CPU1(),
                             check_measure=true,
                             cache=true)

Construct a model wrapper for hyperparameter optimization of a
supervised learner.

Calling `fit!(mach)` on a machine `mach=machine(tuned_model, X, y)` or
`mach=machine(tuned_model, X, y, w)` will:

- Instigate a search, over clones of `model`, with the hyperparameter
  mutations specified by `range`, for a model optimizing the specified
  `measure`, using performance evaluations carried out using the
  specified `tuning` strategy and `resampling` strategy.

- Fit an internal machine, based on the optimal model
  `fitted_params(mach).best_model`, wrapping the optimal `model`
  object in *all* the provided data `X`, `y`(, `w`). Calling
  `predict(mach, Xnew)` then returns predictions on `Xnew` of this
  internal machine. The final train can be supressed by setting
  `train_best=false`.

The `range` objects supported depend on the `tuning` strategy
specified. Query the `strategy` docstring for details. To optimize
over an explicit list `v` of models of the same type, use
`strategy=Explicit()` and specify `model=v[1]` and `range=v`.

The number of models searched is specified by `n`. If unspecified,
then `MLJTuning.default_n(tuning, range)` is used. When `n` is
increased and `fit!(mach)` called again, the old search history is
re-instated and the search continues where it left off.

If `measure` supports weights (`supports_weights(measure) == true`)
then any `weights` specified will be passed to the measure. If more
than one `measure` is specified, then only the first is optimized
(unless `strategy` is multi-objective) but the performance against
every measure specified will be computed and reported in
`report(mach).best_performance` and other relevant attributes of the
generated report.

Specify `repeats > 1` for repeated resampling per model
evaluation. See [`evaluate!`](@ref) options for details.

*Important.* If a custom `measure` is used, and the measure is
a score, rather than a loss, be sure to check that
`MLJ.orientation(measure) == :score` to ensure maximization of the
measure, rather than minimization. Override an incorrect value with
`MLJ.orientation(::typeof(measure)) = :score`.

In the case of two-parameter tuning, a Plots.jl plot of performance
estimates is returned by `plot(mach)` or `heatmap(mach)`.

Once a tuning machine `mach` has bee trained as above, then
`fitted_params(mach)` has these keys/values:

key                 | value
--------------------|--------------------------------------------------
`best_model`        | optimal model instance
`best_fitted_params`| learned parameters of the optimal model

The named tuple `report(mach)` includes these keys/values:

key                 | value
--------------------|--------------------------------------------------
`best_model`        | optimal model instance
`best_history_entry`| corresponding entry in the history, including performance estimate
`best_report`       | report generated by fitting the optimal model to all data
`history`           | tuning strategy-specific history of all evaluations

plus other key/value pairs specific to the `tuning` strategy.

### Summary of key-word arguments

- `model`: `Supervised` model prototype that is cloned and mutated to
  generate models for evaluation

- `tuning=Grid()`: tuning strategy to be applied (eg, `RandomSearch()`)

- `resampling=Holdout()`: resampling strategy (eg, `Holdout()`, `CV()`),
  `StratifiedCV()`) to be applied in performance evaluations

- `measure`: measure or measures to be applied in performance
  evaluations; only the first used in optimization (unless the
  strategy is multi-objective) but all reported to the history

- `weights`: sample weights to be passed the measure(s) in performance
  evaluations, if supported.

- `repeats=1`: for generating train/test sets multiple times in
  resampling; see [`evaluate!`](@ref) for details

- `operation=predict`: operation to be applied to each fitted model;
  usually `predict` but `predict_mean`, `predict_median` or
  `predict_mode` can be used for `Probabilistic` models, if
  the specified measures are `Deterministic`

- `range`: range object; tuning strategy documentation describes
  supported types

- `selection_heuristic`: the rule determining how the best model is
  decided. According to the default heuristic,
  `NaiveSelection()`, `measure` (or the first
  element of `measure`) is evaluated for each resample and these
  per-fold measurements are aggregrated. The model with the lowest
  (resp. highest) aggregate is chosen if the measure is a `:loss`
  (resp. a `:score`).

- `n`: number of iterations (ie, models to be evaluated); set by
  tuning strategy if left unspecified

- `train_best=true`: whether to train the optimal model

- `acceleration=default_resource()`: mode of parallelization for
  tuning strategies that support this

- `acceleration_resampling=CPU1()`: mode of parallelization for
  resampling

- `check_measure=true`: whether to check `measure` is compatible with the
  specified `model` and `operation`)

- `cache=true`: whether to cache model-specific representations of
  user-suplied data; set to `false` to conserve memory. Speed gains
  likely limited to the case `resampling isa Holdout`.

"""
function TunedModel(; model=nothing,
                    tuning=Grid(),
                    resampling=MLJBase.Holdout(),
                    measures=nothing,
                    measure=measures,
                    weights=nothing,
                    operation=predict,
                    ranges=nothing,
                    range=ranges,
                    selection_heuristic=NaiveSelection(),
                    train_best=true,
                    repeats=1,
                    n=nothing,
                    acceleration=default_resource(),
                    acceleration_resampling=CPU1(),
                    check_measure=true,
                    cache=true)

    range === nothing && error("You need to specify `range=...`.")
    model == nothing && error("You need to specify model=... .\n"*
                              "If `tuning=Explicit()`, any model in the "*
                              "range will do. ")

    if model isa Deterministic
        tuned_model = DeterministicTunedModel(model, tuning, resampling,
                                              measure, weights, operation,
                                              range, selection_heuristic,
                                              train_best, repeats, n,
                                              acceleration,
                                              acceleration_resampling,
                                              check_measure,
                                              cache)
    elseif model isa Probabilistic
        tuned_model = ProbabilisticTunedModel(model, tuning, resampling,
                                              measure, weights, operation,
                                              range, selection_heuristic,
                                              train_best, repeats, n,
                                              acceleration,
                                              acceleration_resampling,
                                              check_measure,
                                              cache)
    else
        error("Only `Deterministic` and `Probabilistic` "*
              "model types supported.")
    end

    message = clean!(tuned_model)
    isempty(message) || @info message

    return tuned_model

end

function MLJBase.clean!(tuned_model::EitherTunedModel)
    message = ""
    if tuned_model.measure === nothing
        tuned_model.measure = default_measure(tuned_model.model)
        if tuned_model.measure === nothing
            error("Unable to deduce a default measure for specified model. "*
                  "You must specify `measure=...`. ")
        else
            message *= "No measure specified. "*
            "Setting measure=$(tuned_model.measure). "
        end
    end

    message *= MLJBase.clean!(tuned_model.tuning)

    if !supports_heuristic(tuned_model.tuning, tuned_model.selection_heuristic)
        message *= "`selection_heuristic=$(tuned_model.selection_heuristic)` "*
        "is not supported by $(tuned_model.tuning). Resetting to "*
        "`NaiveSelectionment()`."
        tuned_model.selection_heuristic = NaiveSelection()
    end

    if (tuned_model.acceleration isa CPUProcesses &&
        tuned_model.acceleration_resampling isa CPUProcesses)
        message *=
        "The combination acceleration=$(tuned_model.acceleration) and"*
        " acceleration_resampling=$(tuned_model.acceleration_resampling) is"*
        "  not generally optimal. You may want to consider setting"*
        " `acceleration = CPUProcesses()` and"*
        " `acceleration_resampling = CPUThreads()`."
    end

    if (tuned_model.acceleration isa CPUThreads &&
        tuned_model.acceleration_resampling isa CPUProcesses)
        message *=
        "The combination acceleration=$(tuned_model.acceleration) and"*
        " acceleration_resampling=$(tuned_model.acceleration_resampling) isn't"*
        " supported. \n Resetting to"*
        " `acceleration = CPUProcesses()` and"*
        " `acceleration_resampling = CPUThreads()`."

        tuned_model.acceleration = CPUProcesses()
        tuned_model.acceleration_resampling = CPUThreads()
    end

    tuned_model.acceleration =
        _process_accel_settings(tuned_model.acceleration)

    return message
end


## FIT AND UPDATE METHODS

# A *metamodel* is either a `Model` instance, `model`, or a tuple
# `(model, s)`, where `s` is extra data associated with `model` that
# the tuning strategy implementation wants available to the `result`
# method for recording in the history.

_first(m::MLJBase.Model) = m
_last(m::MLJBase.Model) = nothing
_first(m::Tuple{Model,Any}) = first(m)
_last(m::Tuple{Model,Any}) = last(m)

# returns a (model, result) pair for the history (called by one of the
# `assemble_events!` methods):
function event!(metamodel,
               resampling_machine,
               verbosity,
               tuning,
               history,
               state)
    model = _first(metamodel)
    metadata = _last(metamodel)
    resampling_machine.model.model = model
    verb = (verbosity >= 2 ? verbosity - 3 : verbosity - 1)
    fit!(resampling_machine, verbosity=verb)
    E = evaluate(resampling_machine)
    entry0 = (model       = model,
              measure     = E.measure,
              measurement = E.measurement,
              per_fold    = E.per_fold,
              metadata    = metadata)
    entry = merge(entry0, extras(tuning, history, state, E))
    if verbosity > 2
        println("hyperparameters: $(params(model))")
    end

    if verbosity > 1
        println("measurement: $(E.measurement[1])")
    end
    return entry
end

function assemble_events!(metamodels,
                         resampling_machine,
                         verbosity,
                         tuning,
                         history,
                         state,
                         acceleration::CPU1)

     n_metamodels = length(metamodels)

     p = Progress(n_metamodels,
         dt = 0,
         desc = "Evaluating over $(n_metamodels) metamodels: ",
         barglyphs = BarGlyphs("[=> ]"),
         barlen = 25,
         color = :yellow)

    verbosity !=1 || update!(p,0)

    entries = map(metamodels) do m
        r = event!(m, resampling_machine, verbosity, tuning, history, state)
        verbosity < 1 || begin
                  p.counter += 1
                  ProgressMeter.updateProgress!(p)
                end
        r
      end

    return entries
end

function assemble_events!(metamodels,
                         resampling_machine,
                         verbosity,
                         tuning,
                         history,
                         state,
                         acceleration::CPUProcesses)

    n_metamodels = length(metamodels)

    entries = @sync begin
        channel = RemoteChannel(()->Channel{Bool}(min(1000, n_metamodels)), 1)
        p = Progress(n_metamodels,
                     dt = 0,
                     desc = "Evaluating over $n_metamodels metamodels: ",
                     barglyphs = BarGlyphs("[=> ]"),
                     barlen = 25,
                     color = :yellow)

        # printing the progress bar
        verbosity < 1 || begin
            update!(p,0)
            @async while take!(channel)
                p.counter +=1
                ProgressMeter.updateProgress!(p)
            end
        end


        ret = @distributed vcat for m in metamodels
            r = event!(m, resampling_machine, verbosity, tuning, history, state)
            verbosity < 1 || begin
                put!(channel, true)
            end
            r
        end
        verbosity < 1 || put!(channel, false)
        ret
    end

    return entries
end

@static if VERSION >= v"1.3.0-DEV.573"
# one machine for each thread; cycle through available threads:
function assemble_events!(metamodels,
                         resampling_machine,
                         verbosity,
                         tuning,
                         history,
                         state,
                         acceleration::CPUThreads)

    if Threads.nthreads() == 1
        return assemble_events!(metamodels,
                         resampling_machine,
                         verbosity,
                         tuning,
                         history,
                         state,
                         CPU1())
   end

    n_metamodels = length(metamodels)
    ntasks = acceleration.settings
    partitions = chunks(1:n_metamodels, ntasks)
    #tasks = Vector{Task}(undef, length(partitions))
    entries = Vector(undef, length(partitions))
    p = Progress(n_metamodels,
         dt = 0,
         desc = "Evaluating over $(n_metamodels) metamodels: ",
         barglyphs = BarGlyphs("[=> ]"),
         barlen = 25,
         color = :yellow)
    ch = Channel{Bool}(min(1000, length(partitions)) )

    @sync begin
        # printing the progress bar
        verbosity < 1 || begin
            update!(p,0)
            @async while take!(ch)
                p.counter +=1
                ProgressMeter.updateProgress!(p)
            end
        end
        # One resampling_machine per task
         machs = [resampling_machine,
                 [machine(Resampler(
                     model= resampling_machine.model.model,
                     resampling    = resampling_machine.model.resampling,
                     measure       = resampling_machine.model.measure,
                     weights       = resampling_machine.model.weights,
                     operation     = resampling_machine.model.operation,
                     check_measure = resampling_machine.model.check_measure,
                     repeats       = resampling_machine.model.repeats,
                     acceleration  = resampling_machine.model.acceleration,
                     cache         = resampling_machine.model.cache),
                          resampling_machine.args...; cache=false) for
                  _ in 2:length(partitions)]...]

        @sync for (i, parts) in enumerate(partitions)
            Threads.@spawn begin
                entries[i] =  map(metamodels[parts]) do m
                    r = event!(m, machs[i],
                              verbosity, tuning, history, state)
                    verbosity < 1 || put!(ch, true)
                    r
                end
            end
        end
        verbosity < 1 || put!(ch, false)
    end
    reduce(vcat, entries)
end

end # of if VERSION ...

# history is intialized to `nothing` because it's type is not known.
_vcat(history, Δhistory) = vcat(history, Δhistory)
_vcat(history::Nothing, Δhistory) = Δhistory
_length(history) = length(history)
_length(::Nothing) = 0

# builds on an existing `history` until the length is `n` or the model
# supply is exhausted (method shared by `fit` and `update`). Returns
# the bigger history. Called by `fit` and `update`.
function build!(history,
               n,
               tuning,
               model,
               model_buffer,
               state,
               verbosity,
               acceleration,
               resampling_machine)
    j = _length(history)
    models_exhausted = false

    # before generating new models be sure to exhaust the model
    # buffer:
    if isready(model_buffer)
        metamodels = [take!(model_buffer),]
        j += 1
        while isready(model_buffer) && j < n
            push!(metamodels, take!(model_buffer))
            j += 1
        end
        Δhistory = assemble_events!(metamodels,
                                    resampling_machine,
                                    verbosity,
                                    tuning,
                                    history,
                                    state,
                                    acceleration)
        history = _vcat(history, Δhistory)
    end

    while j < n && !models_exhausted
        metamodels, state  = MLJTuning.models(tuning,
                                              model,
                                              history,
                                              state,
                                              n - j,
                                              verbosity)
        Δj = _length(metamodels)
        Δj == 0 && (models_exhausted = true)
        shortfall = n - j - Δj
        if models_exhausted && shortfall > 0 && verbosity > -1
            @info "Only $j (of $n) models evaluated.\n"*
            "Model supply exhausted. "
        end
        Δj == 0 && break
        if shortfall < 0 # ie, we have a surplus of models
            # add surplus to buffer:
            for i in (n - j + 1):length(metamodels)
                put!(model_buffer, metamodels[i])
            end
            # and truncate:
            metamodels = metamodels[1:n - j]
        end

        Δhistory = assemble_events!(metamodels,
                                   resampling_machine,
                                   verbosity,
                                   tuning,
                                   history,
                                   state,
                                   acceleration)
        history = _vcat(history, Δhistory)
        j += Δj

    end
    return history, state
end

# given complete history, pick out best model, fit it on all data and
# generate report and cache (meta_state):
function finalize(tuned_model,
                  model_buffer,
                  history,
                  state,
                  verbosity,
                  rm,
                  data...)
    model = tuned_model.model
    tuning = tuned_model.tuning

    user_history = map(history) do entry
        delete(entry, :metadata)
    end

    entry =  best(tuned_model.selection_heuristic, history)
    best_model = entry.model
    best_history_entry = delete(entry, :metadata)
    fitresult = machine(best_model, data...)

    report0 = (best_model         = best_model,
               best_history_entry = best_history_entry,
               history            = user_history)

    if tuned_model.train_best
        fit!(fitresult, verbosity=verbosity - 1)
        report1 = merge(report0, (best_report=MLJBase.report(fitresult),))
    else
        report1 = merge(report0, (best_report=missing,))
    end

    report = merge(report1, tuning_report(tuning, history, state))
    meta_state = (history, deepcopy(tuned_model), model_buffer, state, rm)

    return fitresult, meta_state, report
end

function MLJBase.fit(tuned_model::EitherTunedModel{T,M},
                     verbosity::Integer, data...) where {T,M}
    tuning = tuned_model.tuning
    model = tuned_model.model
    _range = tuned_model.range
    n = tuned_model.n === nothing ?
        default_n(tuning, _range) : tuned_model.n

    verbosity < 1 || @info "Attempting to evaluate $n models."

    acceleration = tuned_model.acceleration

    state = setup(tuning, model, _range, tuned_model.n, verbosity)
    model_buffer = Channel(Inf)

    # instantiate resampler (`model` to be replaced with mutated
    # clones during iteration below):
    resampler = Resampler(model=model,
                          resampling    = tuned_model.resampling,
                          measure       = tuned_model.measure,
                          weights       = tuned_model.weights,
                          operation     = tuned_model.operation,
                          check_measure = tuned_model.check_measure,
                          repeats       = tuned_model.repeats,
                          acceleration  = tuned_model.acceleration_resampling,
                          cache         = tuned_model.cache)
    resampling_machine = machine(resampler, data...; cache=false)
    history, state = build!(nothing, n, tuning, model, model_buffer, state,
                           verbosity, acceleration, resampling_machine)

    rm = resampling_machine
    return finalize(tuned_model, model_buffer,
                    history, state, verbosity, rm, data...)

end

function MLJBase.update(tuned_model::EitherTunedModel,
                        verbosity::Integer,
                        old_fitresult, old_meta_state, data...)

    history, old_tuned_model, model_buffer, state, resampling_machine =
        old_meta_state
    acceleration = tuned_model.acceleration

    tuning = tuned_model.tuning
    range = tuned_model.range
    model = tuned_model.model

    # exclamation points are for values actually used rather than
    # stored:
    n! = tuned_model.n === nothing ?
        default_n(tuning, range) : tuned_model.n

    old_n! = old_tuned_model.n === nothing ?
        default_n(tuning, range) : old_tuned_model.n

    if MLJBase.is_same_except(tuned_model, old_tuned_model, :n) &&
        n! >= old_n!

        verbosity < 1 || @info "Attempting to add $(n! - old_n!) models "*
        "to search, bringing total to $n!. "

        history, state = build!(history, n!, tuning, model, model_buffer, state,
                               verbosity, acceleration, resampling_machine)

        rm = resampling_machine
        return finalize(tuned_model, model_buffer,
                        history, state, verbosity, rm, data...)
    else
        return  fit(tuned_model, verbosity, data...)
    end
end

MLJBase.predict(tuned_model::EitherTunedModel, fitresult, Xnew) =
    predict(fitresult, Xnew)

function MLJBase.fitted_params(tuned_model::EitherTunedModel, fitresult)
    if tuned_model.train_best
        return (best_model=fitresult.model,
                best_fitted_params=fitted_params(fitresult))
    else
        return (best_model=fitresult.model,
                best_fitted_params=missing)
    end
end


## SUPPORT FOR MLJ ITERATION API

MLJBase.iteration_parameter(::Type{<:EitherTunedModel}) = :n
MLJBase.supports_training_losses(::Type{<:EitherTunedModel}) = true

function MLJBase.training_losses(tuned_model::EitherTunedModel, _report)
    _losses = MLJTuning.losses(tuned_model.selection_heuristic, _report.history)
    MLJTuning._length(_losses) == 0 && return nothing

    ret = similar(_losses)
    lowest = first(_losses)
    for i in eachindex(_losses)
        current = _losses[i]
        lowest = min(current, lowest)
        ret[i] = lowest
    end
    return ret
end


## METADATA

MLJBase.is_wrapper(::Type{<:EitherTunedModel}) = true
MLJBase.supports_weights(::Type{<:EitherTunedModel{<:Any,M}}) where M =
    MLJBase.supports_weights(M)
MLJBase.load_path(::Type{<:ProbabilisticTunedModel}) =
    "MLJTuning.ProbabilisticTunedModel"
MLJBase.load_path(::Type{<:DeterministicTunedModel}) =
    "MLJTuning.DeterministicTunedModel"
MLJBase.package_name(::Type{<:EitherTunedModel}) = "MLJTuning"
MLJBase.package_uuid(::Type{<:EitherTunedModel}) =
    "03970b2e-30c4-11ea-3135-d1576263f10f"
MLJBase.package_url(::Type{<:EitherTunedModel}) =
    "https://github.com/alan-turing-institute/MLJTuning.jl"
MLJBase.package_license(::Type{<:EitherTunedModel}) = "MIT"
MLJBase.is_pure_julia(::Type{<:EitherTunedModel{T,M}}) where {T,M} =
    MLJBase.is_pure_julia(M)
MLJBase.input_scitype(::Type{<:EitherTunedModel{T,M}}) where {T,M} =
    MLJBase.input_scitype(M)
MLJBase.target_scitype(::Type{<:EitherTunedModel{T,M}}) where {T,M} =
    MLJBase.target_scitype(M)
