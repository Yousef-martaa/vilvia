import enum


class UserRole(str, enum.Enum):
    parent = "parent"
    admin = "admin"


class ChildStage(str, enum.Enum):
    pregnancy = "pregnancy"
    newborn = "newborn"
    months_0_6 = "0_6m"
    months_6_12 = "6_12m"
    years_1_3 = "1_3y"


class ResourceCategory(str, enum.Enum):
    child_development = "child_development"
    feeding = "feeding"
    sleep = "sleep"
    health_safety = "health_safety"
    vaccinations = "vaccinations"
    everyday_guidance = "everyday_guidance"


class ResourceStage(str, enum.Enum):
    pregnancy = "pregnancy"
    newborn = "newborn"
    months_0_6 = "0_6m"
    months_6_12 = "6_12m"
    years_1_3 = "1_3y"


class PostCategory(str, enum.Enum):
    experiences = "experiences"
    qa = "qa"
    child_development = "child_development"
    family_life = "family_life"
    local_recommendations = "local_recommendations"
    meetups = "meetups"


class ReportTargetType(str, enum.Enum):
    post = "post"
    comment = "comment"


class ReportStatus(str, enum.Enum):
    pending = "pending"
    reviewed = "reviewed"
    dismissed = "dismissed"
