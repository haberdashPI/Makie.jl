####
#### Helper functions to make the cloud plot!
####
function cloud_plot_check_args(category_labels, data_array)
    length(category_labels) == length(data_array) || DimensionMismatch("Length of category_labels must match with length of data_array")
    return nothing
end

# Allow to globally set jitter RNG for testing
# A bit of a lazy solution, but it doesn't seem to be desirably to
# pass the RNG through the plotting command
const RAINCLOUD_RNG = Ref{Random.AbstractRNG}(Random.GLOBAL_RNG)

# quick custom function for jitter
rand_localized(min, max) = rand_localized(RAINCLOUD_RNG[], min, max)
rand_localized(RNG::Random.AbstractRNG, min, max) = rand(RNG) * (max - min) .+ min

"""
    rainclouds!(ax, category_labels, data_array; plot_boxplots=true, plot_clouds=true, kwargs...)

Plot a violin (/histogram), boxplot and individual data points with appropriate spacing
between each.

# Arguments
- `ax`: Axis used to place all these plots onto.
- `category_labels`: Typically `Vector{String}` with a label for each element in
  `data_array`
- `data_array`: Typically `Vector{Float64}` used for to represent the datapoints to plot.

# Keywords
- `plot_boxplots=true`: Boolean to show boxplots to summarize distribution of data.
- `clouds=violin`: [violin, hist, nothing] to show cloud plots either as violin or histogram
  plot, or no cloud plot.
- `hist_bins=30`: if `clouds=hist`, this passes down the number of bins to the histogram
  call.
- `gap=0.2`: Distance between elements of x-axis.
- `side=:left`: Can take values of `:left` or `:right`. Determines which side the violin
  plot will be on.
- `center_boxplot=true`: Determines whether or not to have the boxplot be centered in the
  category.
- `dodge`: vector of `Integer`` (length of data) of grouping variable to create multiple
  side-by-side boxes at the same x position
- `dodge_gap = 0.03`: spacing between dodged boxes
- `n_dodge`: the number of categories to dodge (defaults to maximum(dodge))
- `color`: a single color, or a vector of colors, one for each point

## Violin Plot Specific Keywords
- `cloud_width=1.0`: Determines size of violin plot. Corresponds to `width` keyword arg in
`violin`.

## Box Plot Specific Keywords
- `boxplot_width=0.1`: Width of the boxplot in category x-axis absolute terms.
- `whiskerwidth=0.5`: The width of the Q1, Q3 whisker in the boxplot. Value as a portion of
  the `boxplot_width`.
- `strokewidth=1.0`: Determines the stroke width for the outline of the boxplot.
- `show_median=true`: Determines whether or not to have a line should the median value in
  the boxplot.
- `boxplot_nudge=0.075`: Determines the distance away the boxplot should be placed from the
    center line when `center_boxplot` is `false`. This is the value used to recentering the
    boxplot.
- `show_boxplot_outliers`: show outliers in the boxplot as points (usually confusing when
paired with the scatter plot so the default is to not show them)

## Scatter Plot Specific Keywords
- `side_nudge`: Default value is 0.02 if `plot_boxplots` is true, otherwise `0.075` default.
- `jitter_width=0.05`: Determines the width of the scatter-plot bar in category x-axis
  absolute terms.
- `markersize=2`: Size of marker used for the scatter plot.

## Axis General Keywords
- `title`
- `xlabel`
- `ylabel`
"""
@recipe(RainClouds, category_labels, data_array) do scene
    return Attributes(
        side = :left,
        center_boxplot = true,
        # Cloud plot
        cloud_width = 0.75,
        # Box Plot Settings
        boxplot_width = 0.1,
        whiskerwidth =  0.5,
        strokewidth = 1.0,
        show_median = true,
        boxplot_nudge = 0.075,

        gap = 0.2,

        markersize = 2.0,
        dodge = automatic,
        n_dodge = automatic,
        dodge_gap = 0.03,

        plot_boxplots = true,
        show_boxplot_outliers = false,
        clouds = violin,
        hist_bins = 30,

        color = theme(scene, :patchcolor),
        cycle = [:color => :patchcolor],
    )
end

# create_jitter_array(length_data_array; jitter_width = 0.1, clamped_portion = 0.1)
# Returns a array containing random values with a mean of 0, and a values from `-jitter_width/2.0` to `+jitter_width/2.0`, where a portion of a values are clamped right at the edges.
function create_jitter_array(length_data_array; jitter_width = 0.1, clamped_portion = 0.1)
    jitter_width < 0 && ArgumentError("`jitter_width` should be positive.")
    !(0 <= clamped_portion <= 1) || ArgumentError("`clamped_portion` should be between 0.0 to 1.0")

    # Make base jitter, note base jitter minimum-to-maximum span is 1.0
    base_min, base_max = (-0.5, 0.5)
    jitter = [rand_localized(base_min, base_max) for _ in 1:length_data_array]

    # created clamp_min, and clamp_max to clamp a portion of the data
    @assert (base_max - base_min) == 1.0
    @assert (base_max + base_min) / 2.0 == 0
    clamp_min = base_min + (clamped_portion / 2.0)
    clamp_max = base_max - (clamped_portion / 2.0)

    # clamp if need be
    clamp!(jitter, clamp_min, clamp_max)

    # Based on assumptions of clamp_min and clamp_max above
    jitter = jitter * (0.5jitter_width / clamp_max)

    return jitter
end

####
#### Functions that make the cloud plot
####
function plot!(
        ax::Makie.Axis, P::Type{<: RainClouds},
        allattrs::Attributes, category_labels, data_array)

    plot = plot!(ax.scene, P, allattrs, category_labels, data_array)

    if any(x -> x isa AbstractString, category_labels)
        ulabels = unique(category_labels)
        ax.xticks = (1:length(ulabels), ulabels)
    end
    if haskey(allattrs, :title)
        ax.title = allattrs.title[]
    end
    if haskey(allattrs, :xlabel)
        ax.xlabel = allattrs.xlabel[]
    end
    if haskey(allattrs, :ylabel)
        ax.ylabel = allattrs.ylabel[]
    end
    reset_limits!(ax)
    return plot
end

function group_labels(category_labels, data_array)
    grouped = Dict{eltype(category_labels), Vector{Int}}()
    for (label, data_ix) in zip(category_labels, axes(data_array,1))
        push!(get!(grouped, label, eltype(data_array)[]), data_ix)
    end

    return pairs(grouped)
end

function ungroup_labels(category_labels, data_array)
    if eltype(data_array) isa AbstractVector
        @warn "Using a nested array for raincloud is deprected. Read raincloud's documentation and update your usage accordingly."
        data_array_ = reduce(vcat, data_array)
        category_labels_ = similar(category_labels, length(data_array_))
        ix = 0
        for (i, da) in enumerate(data_array)
            category_labels_[axes(da, 1) .+ ix] .= category_labels[i]
            ix += size(da, 1)
        end
        return category_labels_, data_array_
    end
    return category_labels, data_array
end

function convert_arguments(::Type{<: RainClouds}, category_labels, data_array)
    cloud_plot_check_args(category_labels, data_array)
    return (category_labels, data_array)
end


function plot!(plot::RainClouds)
    category_labels = plot.category_labels[]
    data_array = plot.data_array[]
    category_labels, data_array = ungroup_labels(category_labels, data_array)
    if any(ismissing, data_array)
        error("missing values in data not supported. Please filter out any missing values before plotting")
    end

    # Checking kwargs, and assigning defaults if they are not in kwargs
    # General Settings
    # Define where categories should lie
    x_positions = if any(x -> x isa AbstractString, category_labels)
        labels = unique(category_labels)
        pos = Dict(label => i for (i, label) in enumerate(labels))
        [pos[label] for label in category_labels]
    else
        category_labels
    end

    side = plot.side[]
    center_boxplot_bool = plot.center_boxplot[]
    # Cloud plot
    cloud_width =  plot.cloud_width[]
    cloud_width[] < 0 && ArgumentError("`cloud_width` should be positive.")

    # Box Plot Settings
    boxplot_width = plot.boxplot_width[]
    whiskerwidth = plot.whiskerwidth[]
    strokewidth = plot.strokewidth[]
    show_median = plot.show_median[]
    boxplot_nudge = plot.boxplot_nudge[]

    plot_boxplots = plot.plot_boxplots[]
    clouds = plot.clouds[]
    hist_bins = plot.hist_bins[]

    # Scatter Plot defaults dependent on if there is a boxplot
    side_scatter_nudge_default = plot_boxplots ? 0.2 : 0.075
    jitter_width_default = 0.05

    # Scatter Plot Settings
    side_scatter_nudge = to_value(get(plot, :side_nudge, side_scatter_nudge_default))
    side_scatter_nudge < 0 && ArgumentError("`side_nudge` should be positive. Change `side` to :left, :right if you wish.")
    jitter_width = abs(to_value(get(plot, :jitter_width, jitter_width_default)))
    jitter_width < 0 && ArgumentError("`jitter_width` should be positive.")
    markersize = plot.markersize[]


    # Set-up
    (side == :left) && (side_nudge_direction = 1.0)
    (side == :right) && (side_nudge_direction = -1.0)
    side_scatter_nudge_with_direction = side_scatter_nudge * side_nudge_direction
    side_boxplot_nudge_with_direction = boxplot_nudge * side_nudge_direction

    recenter_to_boxplot_nudge_value = center_boxplot_bool ? side_boxplot_nudge_with_direction : 0.0
    plot_boxplots || (recenter_to_boxplot_nudge_value = 0.0)
    # Note: these cloud plots are horizontal
    full_width = jitter_width + side_scatter_nudge +
        (plot_boxplots ? boxplot_width : 0) +
        (!isnothing(clouds) ? cloud_width + abs(recenter_to_boxplot_nudge_value) : 0)

    final_x_positions, width = compute_x_and_width(x_positions .+ recenter_to_boxplot_nudge_value/2, full_width,
                                                    plot.gap[], plot.dodge[],
                                                    plot.n_dodge[], plot.dodge_gap[])
    width_ratio = width / full_width

    jitter = create_jitter_array(length(data_array);
                                    jitter_width = jitter_width*width_ratio)

    if !isnothing(clouds)
        if clouds === violin
            violin!(plot, final_x_positions .- recenter_to_boxplot_nudge_value.*width_ratio, data_array;
                    show_median=show_median, side=side, width=width_ratio*cloud_width, plot.cycle,
                    plot.color, gap=0)
        elseif clouds === hist
            for (_, ixs) in group_labels(category_labels, data_array)
                isempty(ixs) && continue
                xoffset = final_x_positions[ixs[1]] - recenter_to_boxplot_nudge_value
                hist!(plot, view(data_array, ixs); direction=:x, offset=xoffset,
                        scale_to=-cloud_width*width_ratio, 
                        bins=pick_hist_edges(data_array, hist_bins),
                        color=getuniquevalue(plot.color[], ixs))
            end
        else
            error("cloud attribute accepts (violin, hist, nothing), but not: $(clouds)")
        end
    end

    scatter!(plot, final_x_positions .+ side_scatter_nudge_with_direction.*width_ratio .+
             jitter .- recenter_to_boxplot_nudge_value.*width_ratio, data_array; markersize=markersize,
             plot.color, plot.cycle)

    if plot_boxplots
        boxplot!(plot, final_x_positions .+ side_boxplot_nudge_with_direction.*width_ratio .-
                 recenter_to_boxplot_nudge_value.*width_ratio,
                 data_array;
                 strokewidth=strokewidth,
                 whiskerwidth=whiskerwidth*width_ratio,
                 width=boxplot_width*width_ratio,
                 markersize=markersize,
                 show_outliers=plot.show_boxplot_outliers[],
                 color=plot.color,
                 cycle=plot.cycle)
    end

    return plot
end
