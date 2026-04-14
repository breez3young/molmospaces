import time
import logging

from molmo_spaces.policy.learned_policy.pi_policy import PI_Policy
from molmo_spaces.policy.learned_policy.utils import resize_with_pad

import numpy as np
from scipy.spatial.transform import Rotation as R

log = logging.getLogger(__name__)

def ee_pose_to_xyzrpy(ee_pose: np.ndarray) -> np.ndarray:
    T = np.asarray(ee_pose, dtype=np.float64)
    assert T.shape == (4, 4)
    xyz = T[:3, 3]
    rpy = R.from_matrix(T[:3, :3]).as_euler("xyz", degrees=False)  # rad
    return np.concatenate([xyz, rpy])  # [x, y, z, roll, pitch, yaw]


def xyzrpy_to_pose_matrix(xyzrpy: np.ndarray) -> np.ndarray:
    xyzrpy = np.asarray(xyzrpy, dtype=np.float64).reshape(6)
    xyz = xyzrpy[:3]
    rpy = xyzrpy[3:]

    pose = np.eye(4, dtype=np.float64)
    pose[:3, :3] = R.from_euler("xyz", rpy, degrees=False).as_matrix()
    pose[:3, 3] = xyz
    return pose


class PRTS_Policy(PI_Policy):
    """PRTS policy client over websocket.

    Uses the same DROID observation formatting and action decoding path as PI,
    but keeps a dedicated policy identity for evaluation bookkeeping.
    """

    def get_info(self) -> dict:
        info = super().get_info()
        if info.get("policy_name") in {None, "pi"}:
            info["policy_name"] = "prts"
        info["timestamp"] = time.time()
        return info

    def obs_to_model_input(self, obs):
        # self.render(obs)
        if isinstance(obs, list):
            if len(obs) > 1:
                log.warning(
                    "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
                    "WARNING: obs list has %d elements but only using the first one!\n"
                    "This may indicate a batching issue - expected single observation.\n"
                    "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!",
                    len(obs),
                )
            obs = obs[0]
        model_input = {**obs}
        prompt = self.task.get_task_description()

        # For local eval
        if isinstance(obs, list | tuple):
            obs = obs[0]

        grip = np.clip(obs["qpos"]["gripper"][0] / 0.824033, 0, 1)
        exo_camera_key = (
            "droid_shoulder_light_randomization"
            if "droid_shoulder_light_randomization" in obs
            else "exo_camera_1"
        )
        wrist_camera_key = (
            "wrist_camera_zed_mini" if "wrist_camera_zed_mini" in obs else "wrist_camera"
        )

        # exo_image = obs[exo_camera_key]
        # save_dir = os.path.join(os.getcwd(), "debug_exo_images")
        # os.makedirs(save_dir, exist_ok=True)
        # filename = (
        #     f"exo_{int(time.time() * 1000)}_{self._saved_exo_image_count:06d}.png"
        # )
        # save_path = os.path.join(save_dir, filename)
        # try:
        #     cv2.imwrite(save_path, cv2.cvtColor(obs[exo_camera_key], cv2.COLOR_RGB2BGR))
        #     self._saved_exo_image_count += 1
        # except Exception as e:
        #     log.warning(f"Failed to save exo image to {save_path}: {e}")

        # get eef pose state
        eef_pose = ee_pose_to_xyzrpy(np.array(obs['robot_state']['ee_pose']))
        obs_state = np.concatenate(
            [
                eef_pose,
                np.array([0.0], dtype=eef_pose.dtype),
                np.array([grip], dtype=eef_pose.dtype),
            ]
        )

        model_input = {
            "observation/exterior_image_1_left": resize_with_pad(obs[exo_camera_key], 180, 320),
            "observation/wrist_image_left": resize_with_pad(obs[wrist_camera_key], 180, 320),
            "observation/state": obs_state,
            "prompt": prompt.lower(),
        }
        return model_input
    
    def inference_model(self, model_input):
        if self.model is None:
            self.prepare_model()
        if self.starting_time is None:
            self.starting_time = time.time()
        if self.actions_buffer is None or self.current_buffer_index >= self.chunk_size:
            import websockets

            try:
                self.actions_buffer = self.model.infer(model_input)["actions"]
            except websockets.exceptions.ConnectionClosedError:
                log.error("Connection closed error. Attempting to reset connection...")
                self.prepare_model()
                log.info("Sleeping 5s...")
                time.sleep(5)
                log.info("Retrying inference...")
                self.actions_buffer = self.model.infer(model_input)["actions"]
            self.current_buffer_index = 0
        model_output = self.actions_buffer[self.current_buffer_index]
        self.current_buffer_index += 1
        return model_output

    def model_output_to_action(self, model_output):
        gripper_pos = (
            np.array([255.0]) if model_output[6] > self.grasping_threshold else np.array([0.0])
        )
        # target_xyzrpy = np.asarray(model_output[:6], dtype=np.float64).reshape(6)
        new_pose = xyzrpy_to_pose_matrix(model_output[:6].astype(np.float64))
        

        ## compute ik
        kinematics = self.task.env.current_robot.kinematics
        robot_view = self.task.env.current_robot.robot_view

        gripper_mgs = set(robot_view.get_gripper_movegroup_ids())
        mgs_except_gripper = [x for x in robot_view.move_group_ids() if x not in gripper_mgs]

        jp = kinematics.ik(
            "arm",
            new_pose,
            mgs_except_gripper,
            robot_view.get_qpos_dict(),
            robot_view.base.pose,
            rel_to_base=False,
        )
        action = robot_view.get_ctrl_dict()
        if jp is not None:
            action.update({mg_id: jp[mg_id] for mg_id in mgs_except_gripper})

        action["gripper"] = gripper_pos
        return action


        # arm_output = model_output[:7].reshape(
        #     7,
        # )
        # action = {
        #     "arm": arm_output,
        #     "gripper": gripper_pos,
        # }
        # return action