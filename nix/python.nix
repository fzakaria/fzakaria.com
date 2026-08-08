# _plugins/plotnine.rb renders ```plotnine fences by shelling out to this
# interpreter. Pinned here rather than left to the ambient python3 so that
# a chart drawn on a laptop and a chart drawn in CI are the same chart.
{pkgs}:
pkgs.python3.withPackages (ps: [ps.plotnine])
