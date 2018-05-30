
mutable struct Scene <: AbstractScene
    events::Events

    px_area::Node{IRect2D}
    camera::Camera
    camera_controls::RefValue
    limits::Node{FRect3D}

    transformation::Transformation

    plots::Vector{AbstractPlot}
    theme::Attributes
    children::Vector{Scene}
    current_screens::Vector{AbstractScreen}

    function Scene(
            events::Events,
            px_area::Node{IRect2D},
            camera::Camera,
            camera_controls::RefValue,
            limits::Node,
            transformation::Transformation,
            plots::Vector{AbstractPlot},
            theme::Attributes,
            children::Vector{Scene},
            current_screens::Vector{AbstractScreen},
        )
        obj = new(events, px_area, camera, camera_controls, limits, transformation, plots, theme, children, current_screens)
        jl_finalizer(obj) do obj
            # save_print("Freeing scene")
            close_all_nodes(obj.events)
            close_all_nodes(obj.transformation)
            for field in (:px_area, :limits)
                close(getfield(obj, field), true)
            end
            disconnect!(obj.camera)
            empty!(obj.theme)
            empty!(obj.children)
            empty!(obj.current_screens)
            return
        end
        obj
    end
end

# Just indexing into a scene gets you plot 1, plot 2 etc
Base.length(scene::Scene) = length(scene.plots)
Base.endof(scene::Scene) = length(scene.plots)
getindex(scene::Scene, idx::Integer) = scene.plots[idx]


"""
Each argument can be named for a certain plot type `P`. Falls back to `arg1`, `arg2`, etc.
"""
function argument_names(plot::P) where P <: AbstractPlot
    argument_names(P, length(plot.output_args))
end


function argument_names(::Type{<: AbstractPlot}, num_args::Integer)
    # this is called in the indexing function, so let's be a bit efficient
    ntuple(i-> Symbol("arg$i"), num_args)
end


Base.empty!(scene::Scene) = empty!(scene.plots)

limits(scene::Scene) = scene.limits
limits(scene::SceneLike) = scene.parent.limits


# Since we can use Combined like a scene in some circumstances, we define this alias
theme(x::SceneLike, args...) = theme(x.parent, args...)
theme(x::Scene) = x.theme
theme(x::Scene, key) = x.theme[key]


Base.push!(scene::Combined, subscene) = nothing # Combined plots add themselves uppon creation
function Base.push!(scene::Scene, plot::AbstractPlot)
    push!(scene.plots, plot)
    plot.parent[] = scene
    for screen in scene.current_screens
        insert!(screen, scene, plot)
    end
end
function Base.push!(scene::Scene, plot::Combined)
    push!(scene.plots, plot)
    for screen in scene.current_screens
        insert!(screen, scene, plot)
    end
end

events(scene::Scene) = scene.events
events(scene::SceneLike) = events(scene.parent)

camera(scene::Scene) = scene.camera
camera(scene::SceneLike) = camera(scene.parent)

cameracontrols(scene::Scene) = scene.camera_controls[]
cameracontrols(scene::SceneLike) = cameracontrols(scene.parent)

cameracontrols!(scene::Scene, cam) = (scene.camera_controls[] = cam)
cameracontrols!(scene::SceneLike, cam) = cameracontrols(scene.parent, cam)

pixelarea(scene::Scene) = scene.px_area
pixelarea(scene::SceneLike) = pixelarea(scene.parent)

plots(scene::SceneLike) = scene.plots

const _forced_update_scheduled = Ref(false)
function must_update()
    val = _forced_update_scheduled[]
    _forced_update_scheduled[] = false
    val
end
function force_update!()
    _forced_update_scheduled[] = true
end


const current_global_scene = Ref{Any}()

if is_windows()
    function _primary_resolution()
        # ccall((:GetSystemMetricsForDpi, :user32), Cint, (Cint, Cuint), 0, ccall((:GetDpiForSystem, :user32), Cuint, ()))
        # ccall((:GetSystemMetrics, :user32), Cint, (Cint,), 17)
        dc = ccall((:GetDC, :user32), Ptr{Void}, (Ptr{Void},), C_NULL)
        ntuple(2) do i
            Int(ccall((:GetDeviceCaps, :gdi32), Cint, (Ptr{Void}, Cint), dc, (2 - i) + 117))
        end
    end
else
    # TODO implement osx + linux
    _primary_resolution() = (1920, 1080) # everyone should have at least a hd monitor :D
end

function primary_resolution()
    # Since this is pretty low level and os specific + we can't test on all possible
    # computers, I assume we'll have bugs here. Let's not sweat about it too much,
    # we just use primary_resolution to have a good estimate for a default window resolution
    # if this fails, only thing happening will be a too small/big window when the user doesn't give any resolution.
    try
        _primary_resolution()
    catch e
        warn("Could not retrieve primary monitor resolution. A default resolution of (1920, 1080) is assumed!
        Error: $(sprint(io->showerror(io, e))).")
        (1920, 1080)
    end
end
reasonable_resolution() = primary_resolution() .÷ 2

function current_scene()
    if isassigned(current_global_scene)
        current_global_scene[]
    else
        Scene()
    end
end

Scene(::Void) = Scene()

default_theme() = Theme(
    font = "DejaVuSans",
    backgroundcolor = RGBAf0(1,1,1,1),
    color = :black,
    colormap = :viridis
)

function Scene(;
        area = nothing,
        resolution = reasonable_resolution()
    )
    events = Events()
    if area == nothing
        px_area = foldp(IRect(0, 0, resolution), events.window_area) do v0, w_area
            wh = widths(w_area)
            wh = (wh == Vec(0, 0)) ? widths(v0) : wh
            IRect(0, 0, wh)
        end
    else
        px_area = signal_convert(Signal{IRect2D}, area)
    end
    scene = Scene(
        events,
        px_area,
        Camera(px_area),
        RefValue{Any}(EmptyCamera()),
        node(:scene_limits, FRect3D(Vec3f0(0), Vec3f0(1))),
        Transformation(),
        AbstractPlot[],
        default_theme(),
        Scene[],
        AbstractScreen[]
    )
    current_global_scene[] = scene
    scene
end

function Scene(
        scene::Scene;
        events = scene.events,
        px_area = scene.px_area,
        cam = scene.camera,
        camera_controls = scene.camera_controls,
        boundingbox = Node(AABB(Vec3f0(0), Vec3f0(1))),
        transformation = scene.transformation,
        theme = Theme(),
        current_screens = scene.current_screens
    )
    child = Scene(
        events,
        px_area,
        cam,
        camera_controls,
        boundingbox,
        transformation,
        AbstractPlot[],
        merge(theme, default_theme()),
        Scene[],
        current_screens
    )
    push!(scene.children, child)
    child
end

function Scene(scene::Scene, area)
    events = scene.events
    px_area = signal_convert(Signal{IRect2D}, area)
    child = Scene(
        events,
        px_area,
        Camera(px_area),
        RefValue{Any}(EmptyCamera()),
        node(:scene_limits, FRect3D(Vec3f0(0), Vec3f0(1))),
        Transformation(),
        AbstractPlot[],
        default_theme(),
        Scene[],
        scene.current_screens
    )
    push!(scene.children, child)
    child
end

"""
Fetches all plots sharing the same camera
"""
plots_from_camera(scene::Scene) = plots_from_camera(scene, scene.camera)
function plots_from_camera(scene::Scene, camera::Camera, list = AbstractPlot[])
    append!(list, scene.plots)
    for child in scene.children
        child.camera === camera && plots_from_camera(child, camera, list)
    end
    list
end

function flatten_combined(plots::Vector, flat = AbstractPlot[])
    for elem in plots
        if (elem isa Combined)
            flatten_combined(elem.plots, flat)
        else
            push!(flat, elem)
        end
    end
    flat
end


function real_boundingbox(scene::Scene)
    bb = AABB{Float32}()
    for screen in scene.current_screens
        for plot in flatten_combined(plots_from_camera(scene))
            id = object_id(plot)
            haskey(screen.cache, id) || continue
            robj = screen.cache[id]
            bb == AABB{Float32}() && (bb = value(robj.boundingbox))
            bb = union(bb, value(robj.boundingbox))
        end
    end
    bb
end



function insert_plots!(scene::Scene)
    for screen in scene.current_screens
        for elem in scene.plots
            insert!(screen, scene, elem)
        end
    end
    foreach(insert_plots!, scene.children)
end
update_cam!(scene::Scene, bb::AbstractCamera, rect) = nothing
