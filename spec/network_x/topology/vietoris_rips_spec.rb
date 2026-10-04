RSpec.describe NetworkX::Topology do
  def persistence(graph, **kwargs)
    described_class.vietoris_rips_persistence(graph, **kwargs)
  end

  def intervals_in(intervals, dimension)
    intervals.select { |i| i.dimension == dimension }
  end

  context 'with a triangle of unit distances' do
    let(:graph) do
      NetworkX::Graph.new.tap do |g|
        g.add_edge(1, 2, weight: 1)
        g.add_edge(2, 3, weight: 1)
        g.add_edge(1, 3, weight: 1)
      end
    end

    subject(:intervals) { persistence(graph) }

    it 'reports two H0 classes dying at t=1 and one essential class' do
      h0 = intervals_in(intervals, 0)
      expect(h0.map { |i| [i.birth, i.death] }).to eq([[0, 1], [0, 1], [0, Float::INFINITY]])
      expect(h0.map(&:birth_simplex)).to eq([[2], [3], [1]])
      expect(h0.map(&:death_simplex)).to eq([[1, 2], [1, 3], nil])
    end

    it 'reports a zero-length H1 interval filled by the triangle' do
      h1 = intervals_in(intervals, 1)
      expect(h1.size).to eq(1)
      expect(h1.first.birth).to eq(1)
      expect(h1.first.death).to eq(1)
      expect(h1.first.birth_simplex).to eq([2, 3])
      expect(h1.first.death_simplex).to eq([1, 2, 3])
    end
  end

  context 'with a four-cycle of unit distances' do
    let(:graph) do
      NetworkX::Graph.new.tap do |g|
        g.add_edge(1, 2, weight: 1)
        g.add_edge(2, 3, weight: 1)
        g.add_edge(3, 4, weight: 1)
        g.add_edge(1, 4, weight: 1)
      end
    end

    subject(:intervals) { persistence(graph) }

    it 'reports three finite H0 classes and one essential class' do
      h0 = intervals_in(intervals, 0)
      expect(h0.map { |i| [i.birth, i.death] }).to eq([[0, 1], [0, 1], [0, 1], [0, Float::INFINITY]])
    end

    it 'reports an essential H1 class born on the closing edge' do
      h1 = intervals_in(intervals, 1)
      expect(h1.size).to eq(1)
      expect(h1.first.birth).to eq(1)
      expect(h1.first.death).to eq(Float::INFINITY)
      expect(h1.first).to be_essential
      expect(h1.first.birth_simplex).to eq([3, 4])
      expect(h1.first.death_simplex).to be_nil
    end
  end

  context 'with a four-cycle plus one diagonal' do
    let(:graph) do
      NetworkX::Graph.new.tap do |g|
        g.add_edge(1, 2, weight: 1)
        g.add_edge(2, 3, weight: 1)
        g.add_edge(3, 4, weight: 1)
        g.add_edge(1, 4, weight: 1)
        g.add_edge(1, 3, weight: 1)
      end
    end

    subject(:intervals) { persistence(graph) }

    it 'reports two zero-length H1 intervals filled by the two triangles' do
      h1 = intervals_in(intervals, 1)
      expect(h1.map { |i| [i.birth, i.death] }).to eq([[1, 1], [1, 1]])
      expect(h1.map(&:birth_simplex)).to eq([[2, 3], [3, 4]])
      expect(h1.map(&:death_simplex)).to eq([[1, 2, 3], [1, 3, 4]])
    end
  end

  context 'with distinct distances' do
    let(:graph) do
      NetworkX::Graph.new.tap do |g|
        g.add_edge(1, 2, weight: 1)
        g.add_edge(2, 3, weight: 2)
        g.add_edge(3, 4, weight: 3)
        g.add_edge(1, 4, weight: 4)
      end
    end

    subject(:intervals) { persistence(graph) }

    it 'uses edge distances as H0 death times' do
      h0 = intervals_in(intervals, 0)
      expect(h0.map { |i| [i.birth, i.death] }).to eq([[0, 1], [0, 2], [0, 3], [0, Float::INFINITY]])
    end

    it 'births the H1 class at the most expensive edge' do
      h1 = intervals_in(intervals, 1)
      expect(h1.map { |i| [i.birth, i.death] }).to eq([[4, Float::INFINITY]])
      expect(h1.first.birth_simplex).to eq([1, 4])
    end
  end

  context 'with a weighted triangle' do
    let(:graph) do
      NetworkX::Graph.new.tap do |g|
        g.add_edge(1, 2, weight: 1)
        g.add_edge(2, 3, weight: 2)
        g.add_edge(1, 3, weight: 3)
      end
    end

    it 'enters the triangle at the maximum of its edge distances' do
      h1 = intervals_in(persistence(graph), 1)
      expect(h1.map { |i| [i.birth, i.death] }).to eq([[3, 3]])
      expect(h1.first.birth_simplex).to eq([1, 3])
      expect(h1.first.death_simplex).to eq([1, 2, 3])
    end
  end

  context 'with edges lacking a weight attribute' do
    it 'defaults the distance to 1' do
      graph = NetworkX::Graph.new
      graph.add_edge(1, 2)
      expect(intervals_in(persistence(graph), 0).map { |i| [i.birth, i.death] })
        .to eq([[0, 1], [0, Float::INFINITY]])
    end
  end

  context 'with an invalid distance' do
    it 'raises on negative distances' do
      graph = NetworkX::Graph.new
      graph.add_edge(1, 2, weight: -1)
      expect { persistence(graph) }.to raise_error(ArgumentError, /non-negative/)
    end

    it 'raises on non-numeric distances' do
      graph = NetworkX::Graph.new
      graph.add_edge(1, 2, weight: 'far')
      expect { persistence(graph) }.to raise_error(ArgumentError, /non-negative/)
    end
  end

  context 'with a custom weight attribute' do
    it 'reads distances from the given attribute' do
      graph = NetworkX::Graph.new
      graph.add_edge(1, 2, length: 5)
      h0 = intervals_in(persistence(graph, weight: :length), 0)
      expect(h0.map { |i| [i.birth, i.death] }).to eq([[0, 5], [0, Float::INFINITY]])
    end
  end

  context 'with size limits' do
    let(:complete_graph) do
      NetworkX::Graph.new.tap do |g|
        (1..6).to_a.combination(2) { |u, v| g.add_edge(u, v, weight: 1) }
      end
    end

    it 'raises when the vertex limit is exceeded' do
      expect { persistence(complete_graph, max_vertices: 5) }.to raise_error(ArgumentError, /max_vertices/)
    end

    it 'raises when the simplex limit is exceeded' do
      expect { persistence(complete_graph, max_simplices: 10) }.to raise_error(ArgumentError, /max_simplices/)
    end

    it 'accepts explicit limits above the defaults' do
      expect(persistence(complete_graph, max_vertices: 6, max_simplices: 42)).not_to be_empty
    end
  end

  context 'with equal distances' do
    let(:graph) do
      NetworkX::Graph.new.tap do |g|
        g.add_edge(1, 2, weight: 1)
        g.add_edge(2, 3, weight: 1)
        g.add_edge(1, 3, weight: 1)
      end
    end

    it 'is reproducible across calls' do
      first = persistence(graph)
      second = persistence(graph)
      expect(first).to eq(second)
    end

    it 'orders faces before cofaces so deaths never precede births' do
      intervals = persistence(graph)
      intervals.each { |i| expect(i.death).to be >= i.birth }
    end
  end

  context 'with an empty graph' do
    it 'reports no intervals' do
      expect(persistence(NetworkX::Graph.new)).to eq([])
    end
  end

  context 'with a complete graph on four vertices' do
    let(:graph) do
      NetworkX::Graph.new.tap do |g|
        (1..4).to_a.combination(2) { |u, v| g.add_edge(u, v, weight: 1) }
      end
    end

    subject(:intervals) { persistence(graph) }

    it 'reports only H0 and H1 intervals despite truncation artifacts' do
      expect(intervals.map(&:dimension).uniq).to contain_exactly(0, 1)
    end

    it 'fills all three independent cycles with zero-length H1 intervals' do
      h1 = intervals_in(intervals, 1)
      expect(h1.map { |i| [i.birth, i.death] }).to eq([[1, 1], [1, 1], [1, 1]])
    end
  end

  context 'with a single node' do
    it 'reports one essential H0 class' do
      graph = NetworkX::Graph.new
      graph.add_node(1)
      intervals = persistence(graph)
      expect(intervals.size).to eq(1)
      expect(intervals.first.dimension).to eq(0)
      expect(intervals.first.birth_simplex).to eq([1])
      expect(intervals.first.persistence).to eq(Float::INFINITY)
    end
  end
end
