{ system
  , compiler
  , flags
  , pkgs
  , hsPkgs
  , pkgconfPkgs
  , errorHandler
  , config
  , ... }:
  {
    flags = { development = false; };
    package = {
      specVersion = "1.10";
      identifier = { name = "byron-spec-chain"; version = "0.1.0.0"; };
      license = "MIT";
      copyright = "";
      maintainer = "formal.methods@iohk.io";
      author = "IOHK Formal Methods Team";
      homepage = "https://github.com/input-output-hk/cardano-legder-specs";
      url = "";
      synopsis = "Executable specification of the Cardano blockchain";
      description = "";
      buildType = "Simple";
      isLocal = true;
      };
    components = {
      "library" = {
        depends = [
          (hsPkgs."base" or (errorHandler.buildDepError "base"))
          (hsPkgs."bimap" or (errorHandler.buildDepError "bimap"))
          (hsPkgs."bytestring" or (errorHandler.buildDepError "bytestring"))
          (hsPkgs."containers" or (errorHandler.buildDepError "containers"))
          (hsPkgs."byron-spec-ledger" or (errorHandler.buildDepError "byron-spec-ledger"))
          (hsPkgs."goblins" or (errorHandler.buildDepError "goblins"))
          (hsPkgs."hashable" or (errorHandler.buildDepError "hashable"))
          (hsPkgs."hedgehog" or (errorHandler.buildDepError "hedgehog"))
          (hsPkgs."lens" or (errorHandler.buildDepError "lens"))
          (hsPkgs."small-steps" or (errorHandler.buildDepError "small-steps"))
          (hsPkgs."small-steps-test" or (errorHandler.buildDepError "small-steps-test"))
          ];
        buildable = true;
        };
      tests = {
        "chain-rules-test" = {
          depends = [
            (hsPkgs."base" or (errorHandler.buildDepError "base"))
            (hsPkgs."containers" or (errorHandler.buildDepError "containers"))
            (hsPkgs."data-ordlist" or (errorHandler.buildDepError "data-ordlist"))
            (hsPkgs."hedgehog" or (errorHandler.buildDepError "hedgehog"))
            (hsPkgs."lens" or (errorHandler.buildDepError "lens"))
            (hsPkgs."tasty" or (errorHandler.buildDepError "tasty"))
            (hsPkgs."tasty-hedgehog" or (errorHandler.buildDepError "tasty-hedgehog"))
            (hsPkgs."tasty-hunit" or (errorHandler.buildDepError "tasty-hunit"))
            (hsPkgs."byron-spec-chain" or (errorHandler.buildDepError "byron-spec-chain"))
            (hsPkgs."byron-spec-ledger" or (errorHandler.buildDepError "byron-spec-ledger"))
            (hsPkgs."small-steps" or (errorHandler.buildDepError "small-steps"))
            (hsPkgs."small-steps-test" or (errorHandler.buildDepError "small-steps-test"))
            ];
          buildable = true;
          };
        };
      };
    } // {
    src = (pkgs.lib).mkDefault (pkgs.fetchgit {
      url = "https://github.com/input-output-hk/cardano-ledger-specs";
      rev = "a790fb38cced04d8d8a9aeacc2a761717f11f94e";
      sha256 = "0j5sgx7wqf46f30r8dgmxk85y99pvn7dzrj99xi7779lllqn4ddg";
      });
    postUnpack = "sourceRoot+=/byron/chain/executable-spec; echo source root reset to \$sourceRoot";
    }