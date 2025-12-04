'use client';

import { useEffect, useState } from 'react';
import { useZooStore, type ZooEnclosure, type AnimalType } from '@/stores/useZooStore';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { useAdSpeedUp } from '@/hooks/useAdSpeedUp';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import { getItemIcon, getItemName } from '@/lib/itemUtils';
import { useErrorHandler } from '@/hooks/useErrorHandler';

interface EnclosureCardProps {
  enclosure: ZooEnclosure;
  animalTypes: AnimalType[];
  onAddAnimal: (enclosureId: number, animalTypeId: number, slot: number) => void;
  onRemoveAnimal: (enclosureId: number, slot: number) => void;
  onCollectProduction: (enclosureId: number, slot: number) => void;
  onStartBreeding: (enclosureId: number) => void;
  onCollectBred: (enclosureId: number) => void;
}

const EnclosureCard: React.FC<EnclosureCardProps> = ({
  enclosure,
  animalTypes,
  onAddAnimal,
  onRemoveAnimal,
  onCollectProduction,
  onStartBreeding,
  onCollectBred
}) => {
  const [showAnimalModal, setShowAnimalModal] = useState<number | null>(null);
  const { watchAdForSpeedUp, canWatchAd, adsRemaining, loading: adLoading } = useAdSpeedUp();
  const animal1 = enclosure.animal1_id ? animalTypes.find(a => a.id === enclosure.animal1_id) : null;
  const animal2 = enclosure.animal2_id ? animalTypes.find(a => a.id === enclosure.animal2_id) : null;

  const canCollect1 = animal1 && enclosure.animal1_produced_at && 
    new Date(enclosure.animal1_produced_at).getTime() + (animal1.produces_interval_minutes * 60 * 1000) <= Date.now();
  const canCollect2 = animal2 && enclosure.animal2_produced_at && 
    new Date(enclosure.animal2_produced_at).getTime() + (animal2.produces_interval_minutes * 60 * 1000) <= Date.now();
  
  // Can only breed if both animals are the same type and not at max level
  const animalsMatch = animal1 && animal2 && animal1.id === animal2.id;
  const animal1AtMax = enclosure.animal1_level !== null && enclosure.animal1_level >= 10;
  const animal2AtMax = enclosure.animal2_level !== null && enclosure.animal2_level >= 10;
  const canBreed = animalsMatch && !animal1AtMax && !animal2AtMax && !enclosure.breeding_started_at;
  const breedingComplete = enclosure.breeding_completes_at && 
    new Date(enclosure.breeding_completes_at).getTime() <= Date.now();
  
  const animal1Level = enclosure.animal1_level ?? 0;
  const animal2Level = enclosure.animal2_level ?? 0;

  const formatTimeLeft = (completesAt: string): string => {
    const now = Date.now();
    const completes = new Date(completesAt).getTime();
    const diff = completes - now;
    if (diff <= 0) return 'Ready!';
    const minutes = Math.floor(diff / (1000 * 60));
    return `${minutes}m`;
  };

  const handleSelectAnimal = async (animalTypeId: number) => {
    if (showAnimalModal === null) return;
    try {
      await onAddAnimal(enclosure.id, animalTypeId, showAnimalModal);
      setShowAnimalModal(null);
    } catch (error) {
      // Error handled in store
    }
  };

  const handleWatchAd = async (slot: number) => {
    try {
      // Encode enclosure_id and slot: enclosure_id * 10 + slot
      const productionId = enclosure.id * 10 + slot;
      await watchAdForSpeedUp('zoo', productionId);
      // Refresh will happen via realtime subscription
    } catch (error) {
      // Error handled in hook
    }
  };

  return (
    <div className="bg-gradient-to-br from-green-900 to-emerald-900 rounded-2xl p-6 border-2 border-green-500/30 shadow-lg">
      <h3 className="text-xl font-bold text-white mb-4">{enclosure.enclosure_name}</h3>
      
      <div className="grid grid-cols-2 gap-4 mb-4">
        {/* Slot 1 */}
        <div className="bg-white/10 rounded-lg p-4 relative">
          {animal1 ? (
            <>
              <button
                onClick={() => onRemoveAnimal(enclosure.id, 1)}
                className="absolute top-2 right-2 w-6 h-6 flex items-center justify-center bg-red-600 hover:bg-red-500 text-white rounded-full text-xs font-bold transition-colors"
                title="Remove animal"
              >
                ×
              </button>
              <div className="text-center mb-2">
                <span className="text-4xl">{animal1.icon}</span>
                <div className="text-white font-semibold text-sm">{animal1.name}</div>
                {animal1Level > 0 && (
                  <div className="text-yellow-400 text-xs font-bold">+{animal1Level}</div>
                )}
                <div className="text-slate-300 text-xs capitalize">{animal1.rarity}</div>
              </div>
              {canCollect1 && (
                <button
                  onClick={() => onCollectProduction(enclosure.id, 1)}
                  className="w-full px-3 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold text-sm transition-colors"
                >
                  Collect {getItemIcon(animal1.produces_item_id || 0)} {animal1.produces_quantity}
                </button>
              )}
              {!canCollect1 && animal1 && (
                <div className="space-y-2">
                  <div className="text-slate-400 text-xs text-center">Producing...</div>
                  {canWatchAd && (
                    <button
                      onClick={() => handleWatchAd(1)}
                      disabled={adLoading}
                      className="w-full px-2 py-1 bg-green-600 hover:bg-green-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white text-xs rounded-lg font-semibold transition-colors"
                      title={`Watch Ad (${adsRemaining} remaining)`}
                    >
                      📺 Speed Up
                    </button>
                  )}
                </div>
              )}
            </>
          ) : (
            <button
              onClick={() => setShowAnimalModal(1)}
              className="w-full h-full flex items-center justify-center text-slate-400 hover:text-white border-2 border-dashed border-slate-600 rounded-lg p-4 transition-colors"
            >
              + Add Animal
            </button>
          )}
        </div>

        {/* Slot 2 */}
        <div className="bg-white/10 rounded-lg p-4 relative">
          {animal2 ? (
            <>
              <button
                onClick={() => onRemoveAnimal(enclosure.id, 2)}
                className="absolute top-2 right-2 w-6 h-6 flex items-center justify-center bg-red-600 hover:bg-red-500 text-white rounded-full text-xs font-bold transition-colors"
                title="Remove animal"
              >
                ×
              </button>
              <div className="text-center mb-2">
                <span className="text-4xl">{animal2.icon}</span>
                <div className="text-white font-semibold text-sm">{animal2.name}</div>
                {animal2Level > 0 && (
                  <div className="text-yellow-400 text-xs font-bold">+{animal2Level}</div>
                )}
                <div className="text-slate-300 text-xs capitalize">{animal2.rarity}</div>
              </div>
              {canCollect2 && (
                <button
                  onClick={() => onCollectProduction(enclosure.id, 2)}
                  className="w-full px-3 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold text-sm transition-colors"
                >
                  Collect {getItemIcon(animal2.produces_item_id || 0)} {animal2.produces_quantity}
                </button>
              )}
              {!canCollect2 && animal2 && (
                <div className="space-y-2">
                  <div className="text-slate-400 text-xs text-center">Producing...</div>
                  {canWatchAd && (
                    <button
                      onClick={() => handleWatchAd(2)}
                      disabled={adLoading}
                      className="w-full px-2 py-1 bg-green-600 hover:bg-green-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white text-xs rounded-lg font-semibold transition-colors"
                      title={`Watch Ad (${adsRemaining} remaining)`}
                    >
                      📺 Speed Up
                    </button>
                  )}
                </div>
              )}
            </>
          ) : (
            <button
              onClick={() => setShowAnimalModal(2)}
              className="w-full h-full flex items-center justify-center text-slate-400 hover:text-white border-2 border-dashed border-slate-600 rounded-lg p-4 transition-colors"
            >
              + Add Animal
            </button>
          )}
        </div>
      </div>

      {/* Breeding */}
      {enclosure.breeding_started_at && (
        <div className="mb-4 bg-purple-900/50 rounded-lg p-3 text-center">
          {breedingComplete ? (
            <button
              onClick={() => onCollectBred(enclosure.id)}
              className="w-full px-4 py-2 bg-purple-600 hover:bg-purple-500 text-white rounded-lg font-semibold transition-colors"
            >
              Collect Bred Animal! 🎉
            </button>
          ) : (
            <div className="text-white">
              <div className="text-sm mb-1">Breeding in progress...</div>
              <div className="text-xs text-purple-300">{formatTimeLeft(enclosure.breeding_completes_at!)}</div>
            </div>
          )}
        </div>
      )}

      {animal1 && animal2 && !enclosure.breeding_started_at && (
        <>
          {canBreed ? (
            <button
              onClick={() => onStartBreeding(enclosure.id)}
              className="w-full px-4 py-2 bg-purple-600 hover:bg-purple-500 text-white rounded-lg font-semibold transition-colors"
            >
              Start Breeding 💕
            </button>
          ) : (
            <div className="w-full px-4 py-2 bg-slate-700 text-slate-400 rounded-lg text-center text-sm">
              {!animalsMatch ? (
                <span>Can only breed two animals of the same type</span>
              ) : animal1AtMax || animal2AtMax ? (
                <span>Cannot breed animals at maximum level (+10)</span>
              ) : (
                <span>Cannot breed</span>
              )}
            </div>
          )}
        </>
      )}

      {/* Animal Selection Modal */}
      {showAnimalModal !== null && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowAnimalModal(null)}>
          <div className="bg-gradient-to-br from-green-900 to-emerald-900 rounded-2xl p-6 max-w-2xl w-full mx-4 border-2 border-green-500/50 max-h-[80vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-2xl font-bold text-white mb-4">Select Animal for Slot {showAnimalModal}</h3>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-4 mb-4">
              {animalTypes.map((animal) => (
                <button
                  key={animal.id}
                  onClick={() => handleSelectAnimal(animal.id)}
                  className={`bg-gradient-to-br ${
                    animal.rarity === 'legendary' ? 'from-purple-600 to-pink-600' :
                    animal.rarity === 'rare' ? 'from-blue-600 to-indigo-600' :
                    'from-gray-600 to-slate-600'
                  } rounded-xl p-4 border-2 border-white/20 hover:scale-105 transition-all text-left`}
                >
                  <div className="text-center">
                    <div className="text-4xl mb-2">{animal.icon}</div>
                    <div className="text-white font-semibold text-sm mb-1">{animal.name}</div>
                    <div className="text-yellow-400 text-xs mb-1">💎 {animal.base_cost_crystals}</div>
                    <div className="text-white/80 text-xs capitalize">{animal.rarity}</div>
                    {animal.produces_item_id && (
                      <div className="text-white/90 text-xs mt-1">
                        Produces: {getItemIcon(animal.produces_item_id)} every {animal.produces_interval_minutes}m
                      </div>
                    )}
                  </div>
                </button>
              ))}
            </div>
            <button
              onClick={() => setShowAnimalModal(null)}
              className="w-full px-4 py-2 bg-red-600 hover:bg-red-500 text-white rounded-lg font-semibold transition-colors"
            >
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default function ZooPage() {
  const {
    enclosures,
    animalTypes,
    loading,
    error,
    enclosureCostInfo,
    fetchEnclosures,
    fetchAnimalTypes,
    createEnclosure,
    addAnimalToEnclosure,
    removeAnimalFromEnclosure,
    collectProduction,
    startBreeding,
    collectBredAnimal,
    subscribeToZoo
  } = useZooStore();
  const { crystals } = usePlayerStore();
  const { showError } = useErrorHandler();
  const [newEnclosureName, setNewEnclosureName] = useState('');
  const [showCreateModal, setShowCreateModal] = useState(false);
  
  // Wrapper for addAnimalToEnclosure with pre-validation
  const handleAddAnimal = async (enclosureId: number, animalTypeId: number, slot: number) => {
    // Pre-validation: Check if slot is already occupied
    const enclosure = enclosures.find(e => e.id === enclosureId);
    if (enclosure) {
      if (slot === 1 && enclosure.animal1_id !== null) {
        showError(
          'Enclosure Slot Occupied',
          'Slot 1 in this enclosure is already occupied by another animal.',
          { slot: 1 },
          'Select an empty slot or remove the current animal first.'
        );
        return;
      }
      if (slot === 2 && enclosure.animal2_id !== null) {
        showError(
          'Enclosure Slot Occupied',
          'Slot 2 in this enclosure is already occupied by another animal.',
          { slot: 2 },
          'Select an empty slot or remove the current animal first.'
        );
        return;
      }
    }
    
    // Pre-validation: Check if player has enough crystals
    const animalType = animalTypes.find(a => a.id === animalTypeId);
    if (animalType && crystals < animalType.base_cost_crystals) {
      const needed = animalType.base_cost_crystals - crystals;
      showError(
        'Not Enough Crystals',
        `You need ${needed.toLocaleString()} more crystals to purchase this animal.`,
        { resource: 'crystals', required: animalType.base_cost_crystals, available: crystals },
        'Earn more crystals by completing orders, harvesting crops, or selling items.'
      );
      return;
    }
    
    try {
      await addAnimalToEnclosure(enclosureId, animalTypeId, slot);
    } catch (error) {
      // Error already handled in store
    }
  };

  useEffect(() => {
    fetchEnclosures();
    fetchAnimalTypes();
    const unsubscribe = subscribeToZoo();
    return unsubscribe;
  }, [fetchEnclosures, fetchAnimalTypes, subscribeToZoo]);

  const handleCreateEnclosure = async () => {
    if (!newEnclosureName.trim()) {
      showError('Enclosure Name Required', 'Please enter a name for your enclosure.');
      return;
    }
    try {
      await createEnclosure(newEnclosureName.trim());
      setNewEnclosureName('');
      setShowCreateModal(false);
    } catch (error) {
      // Error handled in store
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-green-900 via-emerald-900 to-teal-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Zoo</h1>
          <div className="flex justify-center">
            <Skeleton className="w-full h-64" />
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-green-900 via-emerald-900 to-teal-900 p-4">
      <div className="max-w-6xl mx-auto">
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-3xl font-bold text-white">Zoo</h1>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
              <span className="text-2xl">💎</span>
              <span className="text-white font-mono">{crystals.toLocaleString()}</span>
            </div>
            {enclosureCostInfo && (
              <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
                <span className="text-white text-sm">
                  Enclosures: {enclosureCostInfo.current_count}/{enclosureCostInfo.max_enclosures}
                </span>
              </div>
            )}
            <button
              onClick={() => setShowCreateModal(true)}
              disabled={enclosureCostInfo?.at_limit && crystals < (enclosureCostInfo?.next_cost || 0)}
              className="px-4 py-2 bg-green-600 hover:bg-green-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white rounded-lg font-semibold transition-colors"
            >
              + New Enclosure
              {enclosureCostInfo && enclosureCostInfo.next_cost > 0 && (
                <span className="ml-2 text-xs">({enclosureCostInfo.next_cost} 💎)</span>
              )}
            </button>
          </div>
        </div>

        {error && (
          <div className="mb-6 p-4 bg-red-500/20 border border-red-500/50 rounded-xl text-red-200 text-center">
            {error}
          </div>
        )}

        {/* Enclosures */}
        {enclosures.length === 0 ? (
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-8 text-center">
            <p className="text-slate-300 text-lg mb-4">No enclosures yet</p>
            <p className="text-slate-400 mb-4">Create your first enclosure to start collecting animals!</p>
            {enclosureCostInfo && enclosureCostInfo.next_cost > 0 && (
              <p className="text-yellow-400 text-sm mb-4">
                Next enclosure costs {enclosureCostInfo.next_cost} crystals
              </p>
            )}
            <button
              onClick={() => setShowCreateModal(true)}
              disabled={enclosureCostInfo?.at_limit && crystals < (enclosureCostInfo?.next_cost || 0)}
              className="px-6 py-3 bg-green-600 hover:bg-green-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white rounded-lg font-semibold transition-colors"
            >
              Create Enclosure
            </button>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {enclosures.map((enclosure) => (
              <EnclosureCard
                key={enclosure.id}
                enclosure={enclosure}
                animalTypes={animalTypes}
                onAddAnimal={handleAddAnimal}
                onRemoveAnimal={removeAnimalFromEnclosure}
                onCollectProduction={collectProduction}
                onStartBreeding={startBreeding}
                onCollectBred={collectBredAnimal}
              />
            ))}
          </div>
        )}

        {/* Animal Types Reference */}
        <div className="mt-8">
          <h2 className="text-2xl font-bold text-white mb-4">Available Animals</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {animalTypes.map((animal) => (
              <div
                key={animal.id}
                className={`bg-gradient-to-br ${
                  animal.rarity === 'legendary' ? 'from-purple-600 to-pink-600' :
                  animal.rarity === 'rare' ? 'from-blue-600 to-indigo-600' :
                  'from-gray-600 to-slate-600'
                } rounded-xl p-4 border border-white/20`}
              >
                <div className="text-center">
                  <div className="text-4xl mb-2">{animal.icon}</div>
                  <div className="text-white font-semibold mb-1">{animal.name}</div>
                  <div className="text-yellow-400 text-sm mb-2">💎 {animal.base_cost_crystals}</div>
                  <div className="text-white/80 text-xs capitalize mb-2">{animal.rarity}</div>
                  {animal.produces_item_id && (
                    <div className="text-white/90 text-xs">
                      Produces: {getItemIcon(animal.produces_item_id)} {getItemName(animal.produces_item_id)} every {animal.produces_interval_minutes}m
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Create Enclosure Modal */}
        {showCreateModal && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowCreateModal(false)}>
            <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-slate-700" onClick={(e) => e.stopPropagation()}>
              <h3 className="text-2xl font-bold text-white mb-4">Create Enclosure</h3>
              {enclosureCostInfo && (
                <div className="mb-4 p-3 bg-slate-700/50 rounded-lg">
                  <div className="text-slate-300 text-sm mb-1">
                    Current: {enclosureCostInfo.current_count}/{enclosureCostInfo.max_enclosures} enclosures
                  </div>
                  {enclosureCostInfo.next_cost > 0 && (
                    <div className="text-yellow-400 text-sm">
                      Cost: {enclosureCostInfo.next_cost} crystals
                    </div>
                  )}
                  {enclosureCostInfo.can_create_free && (
                    <div className="text-green-400 text-sm">Free!</div>
                  )}
                </div>
              )}
              <input
                type="text"
                value={newEnclosureName}
                onChange={(e) => setNewEnclosureName(e.target.value)}
                placeholder="Enclosure name..."
                className="w-full px-4 py-2 bg-slate-700 text-white rounded-lg mb-4"
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    handleCreateEnclosure();
                  }
                }}
              />
              <div className="flex gap-2">
                <button
                  onClick={() => setShowCreateModal(false)}
                  className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={handleCreateEnclosure}
                  disabled={enclosureCostInfo?.at_limit && crystals < (enclosureCostInfo?.next_cost || 0)}
                  className="flex-1 px-4 py-2 bg-green-600 hover:bg-green-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white rounded-lg font-semibold transition-colors"
                >
                  Create
                  {enclosureCostInfo && enclosureCostInfo.next_cost > 0 && (
                    <span className="ml-2">({enclosureCostInfo.next_cost} 💎)</span>
                  )}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

