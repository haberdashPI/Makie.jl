@testset "Basic Figures" begin
    fig = Figure()
    @test current_figure() === fig

    fig2 = Figure()
    @test fig !== fig2
    @test current_figure() === fig2

    current_figure!(fig)
    @test current_figure() === fig
end

@testset "FigureAxisPlot" begin
    fap = scatter(rand(100, 2))
    @test fap isa AbstractPlotting.FigureAxisPlot
    fig, ax, p = scatter(rand(100, 2))
    @test fig isa Figure
    @test ax isa Axis
    @test p isa Scatter

    fig2, ax2, p2 = scatter(rand(100, 3))
    @test fig2 isa Figure
    @test ax2 isa LScene # 3d plot
    @test p2 isa Scatter
end

@testset "AxisPlot and Axes" begin
    fig = Figure()
    @test current_axis() === nothing
    @test current_figure() === fig

    figurepos = fig[1, 1]
    @test figurepos isa AbstractPlotting.FigurePosition
    ap = scatter(figurepos, rand(100, 2))
    @test ap isa AbstractPlotting.AxisPlot
    @test current_axis() === ap.axis

    ax2, p2 = scatter(fig[1, 2], rand(100, 2))
    @test ax2 isa Axis
    @test p2 isa Scatter
    @test current_axis() === ax2

    ax3, p3 = scatter(fig[1, 3], rand(100, 3))
    @test ax3 isa LScene
    @test p3 isa Scatter
    @test current_axis() === ax3

    @test ap.axis in fig.content
    @test ax2 in fig.content
    @test ax3 in fig.content

    current_axis!(fig, ax2)
    @test current_axis(fig) === ax2
    @test current_axis() === ax2

    fig2 = Figure()
    @test current_figure() === fig2
    @test current_axis() === nothing
    @test current_axis(fig) === ax2

    # current axis can also switch current figure when called without figure argument
    current_axis!(ax2)
    @test current_axis() === ax2
    @test current_figure() === fig
end