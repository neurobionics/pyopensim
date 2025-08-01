"""
Basic tests for pyosim
"""

def test_import():
    """Test that pyosim can be imported."""
    import pyosim as osim
    assert osim is not None

def test_pyosim_version():
    """Test that the version of pyosim can be retrieved."""
    import pyosim as osim
    version = osim.__version__
    assert isinstance(version, str)
    assert len(version) > 0

def test_opensim_model_import():
    """Test that OpenSim Model can be imported and instantiated."""
    from pyosim.simulation import Model
    
    # Test that we can create a basic model
    model = Model()
    assert model is not None
    
    # Test basic model operations
    model.setName("TestModel")
    assert model.getName() == "TestModel"