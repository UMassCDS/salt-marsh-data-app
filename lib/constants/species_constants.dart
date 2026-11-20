// Water is recorded as a cover class but never counts toward the 100% cover total.
const Set<String> kCoverExcludedSpeciesCodes = {'WATER'};

// SOP order: Spartina alterniflora, Spartina patens, Distichlis spicata, Salicornia depressa, Bare Ground, Dead Vegetation
const List<String> kDefaultPinnedSpecies = ['SPALT', 'SPPAT', 'DISPI', 'SADEP', 'BARE', 'DEAD'];
