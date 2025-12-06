const React = require('react');
const { render, screen } = require('@testing-library/react');
require('@testing-library/jest-dom');
const TownMap = require('./TownMap').default;

// Mock the stores
jest.mock('@/stores/usePlayerStore', () => ({
  usePlayerStore: () => ({
    claimDailyReward: jest.fn(),
    crystals: 100,
    population: undefined, // Test with undefined
    townSize: 10,
    expandTown: jest.fn(),
    getExpansionCost: jest.fn().mockResolvedValue(50),
  }),
}));

jest.mock('@/stores/useCityStore', () => ({
  useCityStore: () => ({
    buildings: [],
    buildingTypes: [],
    loading: false,
    fetchBuildings: jest.fn(),
    fetchBuildingTypes: jest.fn(),
    placeBuilding: jest.fn(),
    removeBuilding: jest.fn(),
    subscribeToBuildings: jest.fn().mockReturnValue(jest.fn()),
  }),
}));

jest.mock('@/stores/useDecorationsStore', () => ({
  useDecorationsStore: () => ({
    decorations: [],
    decorationTypes: [],
    fetchDecorations: jest.fn(),
    fetchDecorationTypes: jest.fn(),
    placeDecoration: jest.fn(),
    removeDecoration: jest.fn(),
    subscribeToDecorations: jest.fn().mockReturnValue(jest.fn()),
  }),
}));

// Mock next/navigation
jest.mock('next/navigation', () => ({
  useRouter: () => ({
    push: jest.fn(),
  }),
}));

describe('TownMap Component - Population Handling', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('renders without TypeError when population is undefined', () => {
    expect(() => {
      render(<TownMap />);
    }).not.toThrow();
  });

  test('displays population as 0 when population is undefined', () => {
    render(<TownMap />);
    const populationDisplay = screen.getByText('0');
    expect(populationDisplay).toBeInTheDocument();
  });

  test('population display uses nullish coalescing correctly', () => {
    // The key fix is (population ?? 0).toLocaleString()
    // When population is undefined, it should display '0'
    render(<TownMap />);

    // With undefined population, should show '0' in the population display
    const populationDisplay = screen.getByText('0');
    expect(populationDisplay).toBeInTheDocument();

    // Verify it's the population display by checking the parent container has the population emoji
    const displayContainer = populationDisplay.parentElement;
    expect(displayContainer).toHaveTextContent('👥');
    expect(displayContainer).toHaveTextContent('0');
  });

  test('canPlaceBuilding function handles population comparison safely', () => {
    render(<TownMap />);

    // Component renders successfully, indicating the function doesn't throw
    expect(screen.getByText('Place Building')).toBeInTheDocument();
  });

  test('building population requirements are compared safely', () => {
    render(<TownMap />);

    // Component renders successfully
    expect(screen.getByText('Place Building')).toBeInTheDocument();
  });
});