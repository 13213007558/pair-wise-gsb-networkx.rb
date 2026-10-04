require 'spec_helper'

RSpec.describe 'NetworkX.vietoris_rips_persistence' do
  it 'tracks the H1 cycle of a triangle from its closing edge to its filling triangle' do
    graph = NetworkX::Graph.new
    graph.add_weighted_edge(:a, :b, 1)
    graph.add_weighted_edge(:a, :c, 1)
    graph.add_weighted_edge(:b, :c, 1)

    result = NetworkX.vietoris_rips_persistence(graph)

    expect(result[:simplices].map { |simplex| [simplex[:dimension], simplex[:vertices]] }).to eq(
      [
        [0, [:a]],
        [0, [:b]],
        [0, [:c]],
        [1, [:a, :b]],
        [1, [:a, :c]],
        [1, [:b, :c]],
        [2, [:a, :b, :c]]
      ]
    )
    expect(result[:h0]).to eq(
      [
        {dimension: 0, birth: 0, death: Float::INFINITY,
         creator: {dimension: 0, vertices: [:a]}, killer: nil},
        {dimension: 0, birth: 0, death: 1,
         creator: {dimension: 0, vertices: [:b]}, killer: {dimension: 1, vertices: [:a, :b]}},
        {dimension: 0, birth: 0, death: 1,
         creator: {dimension: 0, vertices: [:c]}, killer: {dimension: 1, vertices: [:a, :c]}}
      ]
    )
    expect(result[:h1]).to eq(
      [
        {dimension: 1, birth: 1, death: 1,
         creator: {dimension: 1, vertices: [:b, :c]},
         killer: {dimension: 2, vertices: [:a, :b, :c]}}
      ]
    )
  end

  it 'keeps the four-cycle interval alive until a diagonal and its triangles appear' do
    graph = NetworkX::Graph.new
    [[0, 1], [1, 2], [2, 3], [3, 0]].each { |u, v| graph.add_weighted_edge(u, v, 1) }
    graph.add_weighted_edge(0, 2, 2)

    result = NetworkX.vietoris_rips_persistence(graph)

    expect(result[:h1]).to eq(
      [
        {dimension: 1, birth: 1, death: 2,
         creator: {dimension: 1, vertices: [2, 3]},
         killer: {dimension: 2, vertices: [0, 2, 3]}},
        {dimension: 1, birth: 2, death: 2,
         creator: {dimension: 1, vertices: [0, 2]},
         killer: {dimension: 2, vertices: [0, 1, 2]}}
      ]
    )
    expect(result[:h0].first).to eq(
      dimension: 0,
      birth: 0,
      death: Float::INFINITY,
      creator: {dimension: 0, vertices: [0]},
      killer: nil
    )
    expect(result[:h0].drop(1).map { |interval| [interval[:birth], interval[:death]] }).to eq(
      [[0, 1], [0, 1], [0, 1]]
    )
  end

  it 'keeps one essential H0 interval for each initially disconnected component' do
    graph = NetworkX::Graph.new
    graph.add_node(:a)
    graph.add_node(:b)

    result = NetworkX.vietoris_rips_persistence(graph)

    expect(result[:h1]).to eq([])
    expect(result[:h0].map { |interval| interval[:death] }).to eq(
      [Float::INFINITY, Float::INFINITY]
    )
  end

  it 'keeps the unfilled four-cycle as an essential H1 interval' do
    graph = NetworkX::Graph.new
    [[0, 1], [1, 2], [2, 3], [3, 0]].each { |u, v| graph.add_weighted_edge(u, v, 1) }

    result = NetworkX.vietoris_rips_persistence(graph)

    expect(result[:h1]).to eq(
      [
        {dimension: 1, birth: 1, death: Float::INFINITY,
         creator: {dimension: 1, vertices: [2, 3]}, killer: nil}
      ]
    )
  end

  it 'uses a fixed small graph-size limit before enumerating cliques' do
    graph = NetworkX::Graph.new
    33.times { |index| graph.add_node(index) }

    expect { NetworkX.vietoris_rips_persistence(graph) }.to raise_error(
      ArgumentError, 'graph has 33 nodes; the small-scale limit is 32.'
    )
  end

  it 'rejects directed graphs, multigraphs, and negative edge distances' do
    directed = NetworkX::DiGraph.new
    directed.add_edge(0, 1)
    expect { NetworkX.vietoris_rips_persistence(directed) }.to raise_error(ArgumentError)

    multigraph = NetworkX::MultiGraph.new
    multigraph.add_edge(0, 1)
    multigraph.add_edge(0, 1)
    expect { NetworkX.vietoris_rips_persistence(multigraph) }.to raise_error(ArgumentError)

    weighted = NetworkX::Graph.new
    weighted.add_weighted_edge(0, 1, -1)
    expect { NetworkX.vietoris_rips_persistence(weighted) }.to raise_error(ArgumentError)
  end

  it 'accepts a custom non-negative distance attribute' do
    graph = NetworkX::Graph.new
    graph.add_edge(0, 1, distance: 2)
    graph.add_node(2)

    result = NetworkX.vietoris_rips_persistence(graph, weight_attr: :distance)
    finite_h0 = result[:h0].find { |interval| interval[:death] == 2 }

    expect(finite_h0[:creator][:vertices]).to eq([1])
  end
end
