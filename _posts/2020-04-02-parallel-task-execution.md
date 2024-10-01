---
layout: post
title: Parallel Task Execution
date: 2020-04-02 14:58 -0700
---

A common task is to have a set of tasks; each with their declared dependencies.
This setup exists in a variety of build tools such as _make_ or _rake_

For instance lets consider this hypothetical _Rakefile_ which defines some tasks.

```ruby
task :a => [:b, :c]

task :b => [:d]

task :c

task :d
```

{::nomarkdown}
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="134pt" height="188pt" viewBox="0.00 0.00 134.00 188.00" style="float: left;">
    <g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(4 184)">
        <title>G</title>
        <polygon fill="#ffffff" stroke="transparent" points="-4,4 -4,-184 130,-184 130,4 -4,4"></polygon>
        <!-- a -->
        <g id="node1" class="node">
            <title>a</title>
            <ellipse fill="none" stroke="#000000" cx="63" cy="-162" rx="27" ry="18"></ellipse>
            <text text-anchor="middle" x="63" y="-157.8" font-family="Times,serif" font-size="14.00" fill="#000000">a</text>
        </g>
        <!-- b -->
        <g id="node2" class="node">
            <title>b</title>
            <ellipse fill="none" stroke="#000000" cx="27" cy="-90" rx="27" ry="18"></ellipse>
            <text text-anchor="middle" x="27" y="-85.8" font-family="Times,serif" font-size="14.00" fill="#000000">b</text>
        </g>
        <!-- a&#45;&gt;b -->
        <g id="edge1" class="edge">
            <title>a-&gt;b</title>
            <path fill="none" stroke="#000000" d="M54.2854,-144.5708C50.0403,-136.0807 44.8464,-125.6929 40.1337,-116.2674"></path>
            <polygon fill="#000000" stroke="#000000" points="43.237,-114.6477 35.6343,-107.2687 36.976,-117.7782 43.237,-114.6477"></polygon>
        </g>
        <!-- c -->
        <g id="node3" class="node">
            <title>c</title>
            <ellipse fill="none" stroke="#000000" cx="99" cy="-90" rx="27" ry="18"></ellipse>
            <text text-anchor="middle" x="99" y="-85.8" font-family="Times,serif" font-size="14.00" fill="#000000">c</text>
        </g>
        <!-- a&#45;&gt;c -->
        <g id="edge2" class="edge">
            <title>a-&gt;c</title>
            <path fill="none" stroke="#000000" d="M71.7146,-144.5708C75.9597,-136.0807 81.1536,-125.6929 85.8663,-116.2674"></path>
            <polygon fill="#000000" stroke="#000000" points="89.024,-117.7782 90.3657,-107.2687 82.763,-114.6477 89.024,-117.7782"></polygon>
        </g>
        <!-- d -->
        <g id="node4" class="node">
            <title>d</title>
            <ellipse fill="none" stroke="#000000" cx="27" cy="-18" rx="27" ry="18"></ellipse>
            <text text-anchor="middle" x="27" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">d</text>
        </g>
        <!-- b&#45;&gt;d -->
        <g id="edge3" class="edge">
            <title>b-&gt;d</title>
            <path fill="none" stroke="#000000" d="M27,-71.8314C27,-64.131 27,-54.9743 27,-46.4166"></path>
            <polygon fill="#000000" stroke="#000000" points="30.5001,-46.4132 27,-36.4133 23.5001,-46.4133 30.5001,-46.4132"></polygon>
        </g>
    </g>
</svg>
{:/}

The goal would be to process the list of tasks in _topological order_; however do so in parallel.

A non-parallel topological walk may result in `d -> b -> c -> a` which would take 4 _units_.

However if we were to optimize the processing it would be possible to do it
in `[d, c] -> [b] -> [a]`; 3 _units_.

Topological sort is well understood[^1], however I was not able to find online
a succinct code snippet for doing so in parallel.

{::nomarkdown}
<div style="clear: both"/>
<br/>
{:/}

```ruby
# construct a directed acyclic graph representation
# an adjacency list structure is likely the simplest
graph = compute the directed acyclic graph

# create some form of executor where you can
# submit some jobs;
executor = construct an executor service

# we'll need a mutex to make some code safe
# unless the grap you are using is thread safe
mutex = construct mutex

mutex.synchronize do
    # keep looping until the graph is empty
    until graph.empty?
        # sinks are nodes whose outdegree is 0;
        # which means that there are no
        # edges leaving the node
        sinks = graph.sinks
        sinks.each do |sink|
            # we wrap the task so we can execute
            # some end handling
            executor.submit do
                # run the task!
                task.run
                mutex.synchronize do
                    # remove this task from the graph
                    graph.remove_node sink
                end
                # wake up the loop thread
                mutex.notify
            end
        end
        # wait pauses the thread and releases the lock
        # this is the optimal way to know when to wake up
        mutex.wait
    end
end

```
{: }

Enjoy some parallel task execution now.

[^1]: Common interview question