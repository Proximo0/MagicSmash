"""Copy a pose from one armature to another with different rest poses and proportions (Blender, no add-on).

For each mapped bone the target bone is turned so that it points the way the source bone points in this frame:
    target_world_rot = D * C * target_rest_rot
    D = source_world_rot(frame) * source_rest_rot^-1      what the animation did to the source bone
    C = shortest turn taking the target's rest direction onto the source's rest direction
The hips' travel is scaled by the leg-length ratio.  Bones are set parents first, so children see their parents' pose.
"""
import bpy
from mathutils import Matrix, Vector

# source (KayKit Rig_Medium) -> target (MPFB "game_engine", Unreal-style names)
KAYKIT_TO_GAME = {
    "hips": "pelvis", "spine": "spine_01", "chest": "spine_03", "head": "head",
    "upperarm.l": "upperarm_l", "lowerarm.l": "lowerarm_l", "hand.l": "hand_l",
    "upperarm.r": "upperarm_r", "lowerarm.r": "lowerarm_r", "hand.r": "hand_r",
    "upperleg.l": "thigh_l", "lowerleg.l": "calf_l", "foot.l": "foot_l", "toes.l": "ball_l",
    "upperleg.r": "thigh_r", "lowerleg.r": "calf_r", "foot.r": "foot_r", "toes.r": "ball_r",
}


def _depth(bone):
    d = 0
    while bone.parent:
        bone = bone.parent
        d += 1
    return d


def _world_rest(arm, name):
    return arm.matrix_world @ arm.data.bones[name].matrix_local


def _dir(m):
    return (m.to_3x3() @ Vector((0, 1, 0))).normalized()


class Retarget:
    def __init__(self, src, dst, bone_map, src_hips="hips", dst_hips="pelvis", legs=(("upperleg.l", "foot.l"), ("thigh_l", "foot_l"))):
        self.src, self.dst = src, dst
        self.pairs = [(s, d) for s, d in bone_map.items() if s in src.data.bones and d in dst.data.bones]
        self.pairs.sort(key=lambda p: _depth(dst.data.bones[p[1]]))
        self.src_hips, self.dst_hips = src_hips, dst_hips
        self.rest = {}
        for s, d in self.pairs:
            sr, dr = _world_rest(src, s), _world_rest(dst, d)
            c = _dir(dr).rotation_difference(_dir(sr)).to_matrix()
            self.rest[d] = (sr.to_3x3().inverted(), c @ dr.to_3x3())
        (sa, sb), (da, db) = legs
        sl = (_world_rest(src, sa).translation - _world_rest(src, sb).translation).length
        dl = (_world_rest(dst, da).translation - _world_rest(dst, db).translation).length
        self.scale = dl / sl if sl > 1e-6 else 1.0
        self.src_hips_rest = _world_rest(src, src_hips).translation.copy()
        self.dst_hips_rest = _world_rest(dst, dst_hips).translation.copy()

    def apply(self):
        """Pose the target like the source's current pose (call after scene.frame_set)."""
        src, dst = self.src, self.dst
        vl = bpy.context.view_layer
        vl.update()
        src_w = {s: (src.matrix_world @ src.pose.bones[s].matrix).copy() for s, _ in self.pairs}
        for pb in dst.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        vl.update()
        inv_w = dst.matrix_world.inverted()
        for s, d in self.pairs:
            pb = dst.pose.bones[d]
            sr_inv, cdr = self.rest[d]
            rot = (src_w[s].to_3x3() @ sr_inv) @ cdr
            cur = dst.matrix_world @ pb.matrix
            loc = cur.translation
            if d == self.dst_hips:
                loc = self.dst_hips_rest + (src_w[s].translation - self.src_hips_rest) * self.scale
            m = rot.to_4x4()
            m.translation = loc
            pb.matrix = inv_w @ m
            vl.update()

    def apply_only(self, names):
        """Pose only these target bones like the source's current pose, leaving the rest as they are (an upper body from
        one clip on the legs of another). The bones keep the world direction the source gives them."""
        src, dst = self.src, self.dst
        vl = bpy.context.view_layer
        vl.update()
        src_w = {s: (src.matrix_world @ src.pose.bones[s].matrix).copy() for s, d in self.pairs if d in names}
        inv_w = dst.matrix_world.inverted()
        for s, d in self.pairs:
            if d not in names:
                continue
            pb = dst.pose.bones[d]
            sr_inv, cdr = self.rest[d]
            m = ((src_w[s].to_3x3() @ sr_inv) @ cdr).to_4x4()
            m.translation = (dst.matrix_world @ pb.matrix).translation
            pb.matrix = inv_w @ m
            vl.update()
